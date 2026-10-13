@testable import App
import Core
import XCTest

final class AllowanceForecastHeadlineRuleTests: AllowanceForecastPresentationTestCase {
    private let limitReached = "Limit reached"

    func testAnotherGroupLineAtItsLimitReadsLimitReachedInItsRow() throws {
        let reset = now.addingTimeInterval(2 * 24 * 60 * 60 + 4 * 60 * 60)
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: estimated("weekly", in: 30 * 60, span: 40 * 60),
            extraLines: [
                UsageLine(label: "Monthly", percentage: 100, resetDate: reset, id: "monthly", limitGroup: "claude"),
            ]
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.value, "3%")
        XCTAssertEqual(headline.status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertEqual(presentation.rowLines["monthly"]?.text, limitReached)
        XCTAssertEqual(
            presentation.rowLines["monthly"]?.accessibilityLabel,
            "Limit reached, no more use available until reset"
        )
        XCTAssertNotNil(presentation.rowLines["weekly"])
        XCTAssertNil(presentation.rowLines["five-hour"])
    }

    func testAGroupLineAtItsLimitNeedsNoForecastForItsRowNotice() {
        let presentation = present(weeklyPercentage: 100)

        XCTAssertNil(presentation.headline)
        XCTAssertEqual(presentation.rowLines["weekly"]?.text, limitReached)
    }

    func testLimitReachedOnTheHeadlineLineReplacesTheHeadline() throws {
        let quota = makeQuota(lines: [UsageLine(label: "5-hour window", percentage: 100, id: "five-hour")])

        let presentation = AllowanceForecastPresentation(
            quota: quota,
            forecasts: ["five-hour": forecast("five-hour", .exhausted, uncertainNearLimit: true)],
            now: now
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.value, "100%")
        XCTAssertEqual(headline.status, limitReached)
        XCTAssertNil(headline.detail)
        XCTAssertEqual(headline.accessibilitySentences, ["Limit reached, no more use available until reset"])
        XCTAssertTrue(presentation.rowLines.isEmpty)
    }

    func testEachLineAtItsLimitSaysSoInItsOwnPlace() throws {
        let reset = now.addingTimeInterval(2 * 60 * 60)
        let presentation = present(weeklyPercentage: 100, fiveHourPercentage: 100, fiveHourReset: reset)

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.value, "100%")
        XCTAssertEqual(headline.status, limitReached)
        XCTAssertEqual(headline.detail, QuotaFormatting.countdown(to: reset))
        XCTAssertNil(presentation.rowLines["five-hour"])
        XCTAssertEqual(presentation.rowLines["weekly"]?.text, limitReached)
    }

    func testALineOutsideTheLimitGroupAtItsLimitGetsNoRowNotice() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weeklyGroup: nil,
            weeklyPercentage: 100
        )

        XCTAssertEqual(try XCTUnwrap(presentation.headline).status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertNil(presentation.rowLines["weekly"])
    }

    func testTheHeadlineLinePausedAfterItsProjectedDepletionKeepsTheProviderHeadline() {
        let presentation = present(
            fiveHour: forecast("five-hour", .paused, uncertainNearLimit: true),
            weekly: estimated("weekly", in: 8 * 60 * 60, span: 40 * 60)
        )

        XCTAssertNil(presentation.headline)
        XCTAssertEqual(presentation.rowLines["five-hour"]?.text, "Forecast paused until fresh data arrives")
        XCTAssertNotNil(presentation.rowLines["weekly"])
    }

    func testAnotherLineNearItsLimitLeavesTheHeadlineToTheHeadlineLine() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: forecast("weekly", .learning, uncertainNearLimit: true)
        )

        XCTAssertEqual(try XCTUnwrap(presentation.headline).status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertEqual(presentation.rowLines["weekly"]?.text, "Learning your usage rate…")
    }

    func testAnExhaustedLineBelowTheDisplayedLimitLeavesTheHeadlineAlone() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: forecast("weekly", .exhausted, uncertainNearLimit: true)
        )

        XCTAssertEqual(try XCTUnwrap(presentation.headline).status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertNil(presentation.rowLines["weekly"])
    }

    func testTheComposedHeadlineReadsAsTextAndSentences() throws {
        let headline = try XCTUnwrap(present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: estimated("weekly", in: 30 * 60, span: 40 * 60)
        ).headline)

        let remaining = CoarseDurationFormatting.string(from: 80 * 60, unitsStyle: .full)
        XCTAssertEqual(headline.text, "3% · About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertEqual(
            headline.accessibilityLabel,
            "3%. About \(remaining) of use remaining at recent pace, based on the last \(span(20 * 60))"
        )
    }

    func testAnotherLineThatRunsOutFirstStaysInItsRow() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: estimated("weekly", in: 30 * 60, span: 40 * 60)
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.value, "3%")
        XCTAssertEqual(headline.status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertEqual(headline.detail, "Based on the last \(span(20 * 60))")
        XCTAssertNil(presentation.rowLines["five-hour"])
        XCTAssertEqual(
            presentation.rowLines["weekly"]?.text,
            "About \(abbreviated(30 * 60)) of use remaining · last \(span(40 * 60))"
        )
    }

    func testBeyondResetComposesTheBeyondResetHeadline() throws {
        let presentation = present(
            fiveHour: beyondReset("five-hour"),
            weekly: beyondReset("weekly")
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.value, "3%")
        XCTAssertEqual(headline.status, "Should last until reset")
        XCTAssertEqual(headline.detail, "At your pace over the last \(span(60 * 60))")
        XCTAssertNil(presentation.rowLines["five-hour"])
        XCTAssertEqual(
            presentation.rowLines["weekly"]?.text,
            "Should last until reset · last \(span(60 * 60))"
        )
    }

    func testBeyondResetHeadlineReadsTheFullSentence() throws {
        let headline = try XCTUnwrap(present(fiveHour: beyondReset("five-hour", approximate: true)).headline)

        XCTAssertEqual(headline.value, "3%")
        XCTAssertEqual(
            headline.accessibilitySentences,
            [
                "Should last until reset at your pace over the last \(span(60 * 60))",
                "Timing is approximate",
            ]
        )
    }

    func testBeyondResetNeedsTheHeadlineLineOwnForecast() {
        let presentation = present(weekly: beyondReset("weekly"))

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["weekly"])
    }

    func testBeyondResetIgnoresOtherLinesWithoutARate() throws {
        let withoutRate: [AllowanceForecast.State] = [.learning, .quiet, .tooFarApart, .paused, .insufficient]
        for state in withoutRate {
            let presentation = present(
                fiveHour: beyondReset("five-hour"),
                weekly: forecast("weekly", state)
            )

            let headline = try XCTUnwrap(presentation.headline, "\(state)")
            XCTAssertEqual(headline.status, "Should last until reset", "\(state)")
            XCTAssertNil(presentation.rowLines["five-hour"], "\(state)")
        }
    }

    func testBeyondResetIgnoresAnotherLineNearItsLimit() throws {
        let presentation = present(
            fiveHour: beyondReset("five-hour"),
            weekly: forecast("weekly", .learning, uncertainNearLimit: true)
        )

        XCTAssertEqual(try XCTUnwrap(presentation.headline).status, "Should last until reset")
        XCTAssertNil(presentation.rowLines["five-hour"])
    }

    func testHeadlineNeverChangesWithoutANamedHeadlineLine() {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weeklyPercentage: 100,
            headlineUsageLineId: nil
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
        XCTAssertNil(presentation.rowLines["weekly"])
    }
}
