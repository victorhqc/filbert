@testable import App
import Core
import XCTest

final class AllowanceForecastLongPeriodTests: AllowanceForecastPresentationTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    func testALongPeriodEstimateInTheHeadlineReadsAsCalendarTime() throws {
        let presentation = present(
            weekly: averagePace("weekly", .estimated(depletesAt: now.addingTimeInterval(2 * day))),
            headlineUsageLineId: "weekly"
        )

        let headline = try XCTUnwrap(presentation.headline)
        let remaining = CoarseDurationFormatting.string(from: 2 * day, unitsStyle: .full)
        XCTAssertEqual(headline.status, "Runs out in about \(abbreviated(2 * day))")
        XCTAssertEqual(headline.detail, "At your average pace, based on \(span(3 * day)) of history")
        XCTAssertEqual(
            headline.accessibilitySentences,
            ["Runs out in about \(remaining) at your average pace, based on \(span(3 * day)) of history"]
        )
    }

    func testALongPeriodEstimateInARowReadsAsCalendarTime() {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: averagePace("weekly", .estimated(depletesAt: now.addingTimeInterval(2 * day)))
        )

        XCTAssertEqual(
            presentation.rowLines["weekly"]?.text,
            "Runs out in about \(abbreviated(2 * day)) · \(span(3 * day)) of history"
        )
    }

    func testALongPeriodBeyondResetNamesTheAveragePace() throws {
        let resetsAt = now.addingTimeInterval(4 * day)
        let presentation = present(
            weekly: averagePace("weekly", .beyondReset(resetsAt: resetsAt)),
            headlineUsageLineId: "weekly"
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.status, "Should last until reset")
        XCTAssertEqual(headline.detail, "At your average pace, based on \(span(3 * day)) of history")
        XCTAssertEqual(
            headline.accessibilitySentences,
            ["Should last until reset at your average pace, based on \(span(3 * day)) of history"]
        )
    }

    func testALongPeriodBeyondResetRowKeepsTheShortText() {
        let presentation = present(
            fiveHour: forecast("five-hour", .learning),
            weekly: averagePace("weekly", .beyondReset(resetsAt: now.addingTimeInterval(4 * day)))
        )

        XCTAssertEqual(presentation.rowLines["weekly"]?.text, "Should last until reset · \(span(3 * day)) of history")
        XCTAssertEqual(
            presentation.rowLines["weekly"]?.accessibilityLabel,
            "Should last until reset at your average pace, based on \(span(3 * day)) of history"
        )
    }

    private func averagePace(_ id: String, _ state: AllowanceForecast.State) -> AllowanceForecast {
        AllowanceForecast(usageLineId: id, state: state, observedAt: now, evidenceSpan: 3 * day, pace: .periodAverage)
    }
}
