@testable import App
import Core
import XCTest

final class AllowanceForecastPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testEstimatedHeadlineLineReplacesTheCountdownAndAddsTheEvidenceLine() throws {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: forecast("weekly", .learning)
        )

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertNil(headline.label)
        XCTAssertEqual(headline.value, "3%")
        XCTAssertEqual(headline.status, "About \(abbreviated(80 * 60)) of use remaining")
        XCTAssertEqual(headline.detail, "Based on the last \(CoarseDurationFormatting.evidenceSpan(20 * 60))")
        XCTAssertNil(presentation.rowLines["five-hour"])
        XCTAssertEqual(presentation.rowLines["weekly"]?.text, "Learning your usage rate…")
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
        XCTAssertEqual(headline.detail, "Based on the last \(CoarseDurationFormatting.evidenceSpan(40 * 60))")
        XCTAssertNil(presentation.rowLines["weekly"])
        XCTAssertEqual(
            presentation.rowLines["five-hour"]?.text,
            "About \(abbreviated(80 * 60)) of use remaining · last \(CoarseDurationFormatting.evidenceSpan(20 * 60))"
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
            "Not expected to run out before reset · last \(CoarseDurationFormatting.evidenceSpan(60 * 60))"
        )
    }

    func testBeyondResetWithAnotherGroupLineLearningKeepsTheProviderHeadline() {
        let presentation = present(
            fiveHour: beyondReset("five-hour"),
            weekly: forecast("weekly", .learning)
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
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

    func testExhaustedGroupLineKeepsTheProviderHeadline() {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            weekly: forecast("weekly", .exhausted)
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
    }

    func testHeadlineNeverChangesWithoutANamedHeadlineLine() {
        let presentation = present(
            fiveHour: estimated("five-hour", in: 80 * 60, span: 20 * 60),
            headlineUsageLineId: nil
        )

        XCTAssertNil(presentation.headline)
        XCTAssertNotNil(presentation.rowLines["five-hour"])
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
        let span = CoarseDurationFormatting.evidenceSpan(2 * 60 * 60)
        XCTAssertEqual(
            row.accessibilityLabel,
            "About \(remaining) of use remaining at recent pace, based on the last \(span)"
        )
        XCTAssertNotEqual(try XCTUnwrap(presentation.headline).accessibilityLabel, presentation.headline?.text)
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

    func testEstimatesLongerThanADayDropMinutePrecision() {
        let withMinutes = present(fiveHour: estimated("five-hour", in: 28 * 60 * 60 + 30 * 60, span: 3600))
        let wholeHours = present(fiveHour: estimated("five-hour", in: 28 * 60 * 60, span: 3600))

        XCTAssertEqual(withMinutes.headline, wholeHours.headline)
        XCTAssertEqual(
            CoarseDurationFormatting.string(from: 8 * 24 * 60 * 60 + 5 * 60 * 60),
            CoarseDurationFormatting.string(from: 8 * 24 * 60 * 60)
        )
    }

    func testRenderingAgesTheEstimateWithoutMovingTheDepletionTime() throws {
        let forecasts = ["five-hour": estimated("five-hour", in: 80 * 60, span: 20 * 60)]
        let later = now.addingTimeInterval(20 * 60)

        let presentation = AllowanceForecastPresentation(quota: makeQuota(), forecasts: forecasts, now: later)

        XCTAssertEqual(try XCTUnwrap(presentation.headline).status, "About \(abbreviated(60 * 60)) of use remaining")
    }

    func testForecastsLeaveBudgetPaceAndCompactStatusUnchanged() {
        let reset = now.addingTimeInterval(3 * 24 * 60 * 60)
        let plain = UsageLine(
            label: "Weekly",
            percentage: 40,
            resetDate: reset,
            windowDuration: UsageWindowDuration.week
        )
        let forecastLine = UsageLine(
            label: "Weekly",
            percentage: 40,
            resetDate: reset,
            windowDuration: UsageWindowDuration.week,
            id: "weekly",
            limitGroup: "claude"
        )

        XCTAssertEqual(BudgetPace(line: forecastLine, now: now), BudgetPace(line: plain, now: now))
        XCTAssertEqual(
            QuotaStatusResolver.compactTier(for: makeQuota(lines: [forecastLine]), at: now),
            QuotaStatusResolver.compactTier(for: makeQuota(lines: [plain]), at: now)
        )
    }
}

private extension AllowanceForecastPresentationTests {
    func present(
        fiveHour: AllowanceForecast? = nil,
        weekly: AllowanceForecast? = nil,
        weeklyGroup: String? = "claude",
        headlineUsageLineId: String? = "five-hour"
    ) -> AllowanceForecastPresentation {
        let lines = [
            UsageLine(label: "5-hour window", percentage: 3, id: "five-hour", limitGroup: "claude"),
            UsageLine(label: "Weekly", percentage: 95, id: "weekly", limitGroup: weeklyGroup),
        ]
        var forecasts: [String: AllowanceForecast] = [:]
        forecasts["five-hour"] = fiveHour
        forecasts["weekly"] = weekly
        return AllowanceForecastPresentation(
            quota: makeQuota(lines: lines, headlineUsageLineId: headlineUsageLineId),
            forecasts: forecasts,
            now: now
        )
    }

    func makeQuota(
        lines: [UsageLine] = [UsageLine(label: "5-hour window", percentage: 3, id: "five-hour")],
        headlineUsageLineId: String? = "five-hour"
    ) -> ProviderQuota {
        ProviderQuota(
            providerId: "provider",
            providerName: "Provider",
            headline: "3% · resets in 5 hours",
            lines: lines,
            lastUpdated: now,
            headlineUsageLineId: headlineUsageLineId
        )
    }

    func forecast(_ id: String, _ state: AllowanceForecast.State) -> AllowanceForecast {
        AllowanceForecast(usageLineId: id, state: state, observedAt: now)
    }

    func estimated(
        _ id: String,
        in remaining: TimeInterval,
        span: TimeInterval,
        approximate: Bool = false
    ) -> AllowanceForecast {
        AllowanceForecast(
            usageLineId: id,
            state: .estimated(depletesAt: now.addingTimeInterval(remaining)),
            observedAt: now,
            evidenceSpan: span,
            isApproximate: approximate
        )
    }

    func beyondReset(_ id: String) -> AllowanceForecast {
        AllowanceForecast(
            usageLineId: id,
            state: .beyondReset(resetsAt: now.addingTimeInterval(5 * 60 * 60)),
            observedAt: now,
            evidenceSpan: 60 * 60
        )
    }

    func abbreviated(_ interval: TimeInterval) -> String {
        CoarseDurationFormatting.string(from: interval)
    }
}
