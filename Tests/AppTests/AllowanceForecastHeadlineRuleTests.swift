@testable import App
import Core
import XCTest

final class AllowanceForecastHeadlineRuleTests: AllowanceForecastPresentationTestCase {
    func testLimitReachedOnALineWithoutADescriptorReplacesTheHeadline() throws {
        let reset = now.addingTimeInterval(2 * 24 * 60 * 60 + 4 * 60 * 60)
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: estimated("weekly", in: 30 * 60, span: 40 * 60),
            extraLines: [UsageLine(label: "Monthly", percentage: 100, resetDate: reset, limitGroup: "claude")]
        )

        let headline = try XCTUnwrap(presentation.headline)
        let countdown = QuotaFormatting.countdown(to: reset)
        XCTAssertEqual(headline.label, "Monthly")
        XCTAssertEqual(headline.value, "100%")
        XCTAssertEqual(headline.status, "Limit reached")
        XCTAssertEqual(headline.detail, countdown)
        XCTAssertEqual(
            headline.accessibilitySentences,
            ["Limit reached, no more use available until reset", countdown]
        )
        XCTAssertNotNil(presentation.rowLines["five-hour"])
        XCTAssertNotNil(presentation.rowLines["weekly"])
    }

    func testLimitReachedNeedsNoForecast() throws {
        let presentation = present(weeklyPercentage: 100)

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.label, "Weekly")
        XCTAssertEqual(headline.value, "100%")
        XCTAssertEqual(headline.status, "Limit reached")
        XCTAssertNil(headline.detail)
        XCTAssertEqual(headline.accessibilitySentences, ["Limit reached, no more use available until reset"])
    }

    func testLimitReachedOnTheHeadlineLineShowsNoLabel() throws {
        let quota = makeQuota(lines: [UsageLine(label: "5-hour window", percentage: 100, id: "five-hour")])

        let presentation = AllowanceForecastPresentation(
            quota: quota,
            forecasts: ["five-hour": forecast("five-hour", .exhausted, uncertainNearLimit: true)],
            now: now
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertNil(headline.label)
        XCTAssertEqual(headline.subject, "100%")
        XCTAssertEqual(headline.status, "Limit reached")
        XCTAssertTrue(presentation.rowLines.isEmpty)
    }

    func testTheLineThatResetsLastWinsWhenSeveralLinesReachedTheLimit() throws {
        let daily = now.addingTimeInterval(60 * 60)
        let monthly = now.addingTimeInterval(9 * 24 * 60 * 60)
        let presentation = present(
            extraLines: [
                UsageLine(label: "Daily", percentage: 100, resetDate: daily, limitGroup: "claude"),
                UsageLine(label: "Monthly", percentage: 100, resetDate: monthly, limitGroup: "claude"),
            ]
        )

        XCTAssertEqual(try XCTUnwrap(presentation.headline).label, "Monthly")
    }

    func testLimitReachedOutsideTheLimitGroupLeavesTheHeadlineToTheGroup() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weeklyGroup: nil,
            weeklyPercentage: 100
        )

        XCTAssertEqual(try XCTUnwrap(presentation.headline).status, "About \(abbreviated(80 * 60)) of use remaining")
    }

    func testAGroupLinePausedAfterItsProjectedDepletionKeepsTheProviderHeadline() {
        let presentation = present(
            fiveHour: forecast("five-hour", .paused, uncertainNearLimit: true),
            weekly: estimated("weekly", in: 8 * 60 * 60, span: 40 * 60)
        )

        XCTAssertNil(presentation.headline)
        XCTAssertEqual(presentation.rowLines["five-hour"]?.text, "Forecast paused until fresh data arrives")
        XCTAssertNotNil(presentation.rowLines["weekly"])
    }

    func testAGroupLineWithoutAnEstimateNearItsLimitKeepsTheProviderHeadline() {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: forecast("weekly", .learning, uncertainNearLimit: true)
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
    }

    func testAnExhaustedGroupLineBelowTheDisplayedLimitKeepsTheProviderHeadline() {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: forecast("weekly", .exhausted, uncertainNearLimit: true)
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
    }

    func testEarliestEstimateInTheLimitGroupBindsAndAddsItsLabel() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: estimated("weekly", in: 30 * 60, span: 40 * 60)
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.label, "Weekly")
        XCTAssertEqual(headline.value, "95%")
        XCTAssertEqual(headline.status, "About \(abbreviated(30 * 60)) of use remaining")
        XCTAssertEqual(headline.detail, "Based on the last \(span(40 * 60))")
        XCTAssertNil(presentation.rowLines["weekly"])
        XCTAssertEqual(
            presentation.rowLines["five-hour"]?.text,
            "About \(abbreviated(80 * 60)) of use remaining · last \(span(20 * 60))"
        )
    }

    func testEveryGroupLineBeyondResetComposesTheBeyondResetHeadline() throws {
        let presentation = present(
            fiveHour: beyondReset("five-hour"),
            weekly: beyondReset("weekly")
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertNil(headline.label)
        XCTAssertEqual(headline.value, "3%")
        XCTAssertEqual(headline.status, "Not expected to run out")
        XCTAssertEqual(headline.detail, "before reset at recent pace")
        XCTAssertNil(presentation.rowLines["five-hour"])
        XCTAssertEqual(
            presentation.rowLines["weekly"]?.text,
            "Not expected to run out before reset · last \(span(60 * 60))"
        )
    }

    func testBeyondResetHeadlineReadsTheFullSentence() throws {
        let headline = try XCTUnwrap(present(fiveHour: beyondReset("five-hour", approximate: true)).headline)

        XCTAssertEqual(headline.subject, "3%")
        XCTAssertEqual(
            headline.accessibilitySentences,
            [
                "Not expected to run out before reset at recent pace, based on the last \(span(60 * 60))",
                "Timing is approximate",
            ]
        )
    }

    func testBeyondResetNeedsTheHeadlineLineOwnForecast() {
        let presentation = present(weekly: beyondReset("weekly"))

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["weekly"])
    }

    func testBeyondResetWithAnotherGroupLineLearningKeepsTheProviderHeadline() {
        let presentation = present(
            fiveHour: beyondReset("five-hour"),
            weekly: forecast("weekly", .learning)
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
    }

    func testHeadlineNeverChangesWithoutANamedHeadlineLine() {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weeklyPercentage: 100,
            headlineUsageLineId: nil
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
    }
}
