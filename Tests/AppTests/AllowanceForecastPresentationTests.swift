@testable import App
import Core
import XCTest

final class AllowanceForecastPresentationTests: AllowanceForecastPresentationTestCase {
    private let week: TimeInterval = 7 * 24 * 60 * 60

    func testEstimatedHeadlineLineReplacesTheCountdownAndAddsTheEvidenceLine() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: forecast("weekly", .learning)
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertNil(headline.label)
        XCTAssertEqual(headline.value, "3%")
        XCTAssertEqual(headline.status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertEqual(headline.detail, "Based on the last \(span(20 * 60))")
        XCTAssertNil(presentation.rowLines["five-hour"])
        XCTAssertEqual(presentation.rowLines["weekly"]?.text, "Learning your usage rate…")
    }

    func testWeakerStatesKeepTheProviderHeadlineAndShowOneRowLine() {
        let expectations: [(AllowanceForecast.State, String?)] = [
            (.learning, "Learning your usage rate…"),
            (.quiet, "No recent consumption detected"),
            (.tooFarApart, "Updates too far apart to estimate"),
            (.paused, "Forecast paused until fresh data arrives"),
            (.exhausted, nil),
            (.insufficient, nil),
        ]

        for (state, text) in expectations {
            let presentation = present(fiveHour: forecast("five-hour", state))

            XCTAssertNil(presentation.headline, "\(state)")
            XCTAssertEqual(presentation.rowLines["five-hour"]?.text, text, "\(state)")
            XCTAssertEqual(presentation.rowLines["five-hour"]?.accessibilityLabel, text, "\(state)")
        }
    }

    func testIndependentPoolsNeverCompeteForTheHeadline() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: estimated("weekly", in: 30 * 60, span: 40 * 60),
            weeklyGroup: nil
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertNil(headline.label)
        XCTAssertEqual(headline.status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertNotNil(presentation.rowLines["weekly"])
    }

    func testRowsAssociateByLineIdOnly() {
        let quota = makeQuota(lines: [
            UsageLine(label: "five-hour", percentage: 3),
            UsageLine(label: "Weekly", percentage: 95, id: "weekly"),
        ])
        let forecasts = [
            "five-hour": forecast("five-hour", .learning),
            "unknown": forecast("unknown", .learning),
            "weekly": forecast("weekly", .quiet),
        ]

        let presentation = AllowanceForecastPresentation(quota: quota, forecasts: forecasts, now: now)

        XCTAssertEqual(Set(presentation.rowLines.keys), ["weekly"])
    }

    func testAccessibilityReadsTheFullConditionalSentence() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: estimated("weekly", in: 26 * 60 * 60, span: 2 * 60 * 60)
        )

        let row = try XCTUnwrap(presentation.rowLines["weekly"])
        let remaining = CoarseDurationFormatting.string(from: 26 * 60 * 60, unitsStyle: .full)
        XCTAssertEqual(
            row.accessibilityLabel,
            "About \(remaining) of use remaining at recent pace, based on the last \(span(2 * 60 * 60))"
        )
        let headlineRemaining = CoarseDurationFormatting.string(from: 80 * 60, unitsStyle: .full)
        XCTAssertEqual(
            try XCTUnwrap(presentation.headline).accessibilitySentences,
            ["About \(headlineRemaining) of use remaining at recent pace, based on the last \(span(20 * 60))"]
        )
        XCTAssertFalse(row.text.contains(" left"))
    }

    func testApproximateTimingAppearsOnlyInAccessibilityText() throws {
        let exact = present(
            weekly: estimated("weekly", in: 26 * 60 * 60, span: 2 * 60 * 60),
            weeklyGroup: nil
        )
        let approximate = present(
            weekly: estimated("weekly", in: 26 * 60 * 60, span: 2 * 60 * 60, approximate: true),
            weeklyGroup: nil
        )

        let exactRow = try XCTUnwrap(exact.rowLines["weekly"])
        let approximateRow = try XCTUnwrap(approximate.rowLines["weekly"])
        XCTAssertEqual(approximateRow.text, exactRow.text)
        XCTAssertNotEqual(approximateRow.accessibilityLabel, exactRow.accessibilityLabel)
        XCTAssertFalse(approximateRow.text.contains("approximate"))
    }

    func testApproximateTimingAppearsOnlyInTheHeadlineAccessibilityText() throws {
        let exact = try XCTUnwrap(present(fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60)).headline)
        let approximate = try XCTUnwrap(
            present(fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60, approximate: true)).headline
        )

        XCTAssertEqual(approximate.status, exact.status)
        XCTAssertEqual(approximate.detail, exact.detail)
        XCTAssertEqual(approximate.accessibilitySentences, exact.accessibilitySentences + ["Timing is approximate"])
    }

    func testEstimatesLongerThanADayDropMinutePrecision() {
        let withMinutes = present(fiveHour: estimated("five-hour", in: 28 * 60 * 60 + 30 * 60, span: 3600))
        let wholeHours = present(fiveHour: estimated("five-hour", in: 28 * 60 * 60, span: 3600))

        XCTAssertEqual(withMinutes.headline, wholeHours.headline)
        XCTAssertEqual(
            CoarseDurationFormatting.string(from: 8 * 24 * 60 * 60 + 5 * 60 * 60),
            CoarseDurationFormatting.string(from: 8 * 24 * 60 * 60)
        )
    }

    func testEstimatesLongerThanFourWeeksReadMoreThanFourWeeks() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 5 * week, span: 2 * 60 * 60),
            weekly: estimated("weekly", in: 6 * week, span: 2 * 60 * 60),
            weeklyGroup: nil
        )

        let headline = try XCTUnwrap(presentation.headline)
        let row = try XCTUnwrap(presentation.rowLines["weekly"])
        let fourWeeks = CoarseDurationFormatting.string(from: 4 * week, unitsStyle: .full)
        XCTAssertEqual(headline.status, "More than \(abbreviated(4 * week)) of use remaining")
        XCTAssertEqual(row.text, "More than \(abbreviated(4 * week)) of use remaining · last \(span(2 * 60 * 60))")
        XCTAssertEqual(
            row.accessibilityLabel,
            "More than \(fourWeeks) of use remaining at recent pace, based on the last \(span(2 * 60 * 60))"
        )
    }

    func testAnEstimateOfExactlyFourWeeksIsStillAnEstimate() throws {
        let presentation = present(fiveHour: estimated("five-hour", in: 4 * week, span: 2 * 60 * 60))

        XCTAssertEqual(
            try XCTUnwrap(presentation.headline).status,
            "About \(abbreviated(4 * week)) of use remaining"
        )
    }

    func testRenderingAgesTheEstimateWithoutMovingTheDepletionTime() throws {
        let forecasts = ["five-hour": estimated("five-hour", in: 80 * 60, span: 20 * 60)]
        let later = now.addingTimeInterval(20 * 60)

        let presentation = AllowanceForecastPresentation(quota: makeQuota(), forecasts: forecasts, now: later)

        XCTAssertEqual(try XCTUnwrap(presentation.headline).status, "About \(abbreviated(60 * 60)) of use remaining")
    }
}
