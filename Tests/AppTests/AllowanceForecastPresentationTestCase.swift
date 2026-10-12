@testable import App
import Core
import XCTest

class AllowanceForecastPresentationTestCase: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func present(
        fiveHour: AllowanceForecast? = nil,
        weekly: AllowanceForecast? = nil,
        weeklyGroup: String? = "claude",
        weeklyPercentage: Double = 95,
        extraLines: [UsageLine] = [],
        headlineUsageLineId: String? = "five-hour"
    ) -> AllowanceForecastPresentation {
        let lines = [
            UsageLine(label: "5-hour window", percentage: 3, id: "five-hour", limitGroup: "claude"),
            UsageLine(label: "Weekly", percentage: weeklyPercentage, id: "weekly", limitGroup: weeklyGroup),
        ] + extraLines
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

    func forecast(
        _ id: String,
        _ state: AllowanceForecast.State,
        uncertainNearLimit: Bool = false
    ) -> AllowanceForecast {
        AllowanceForecast(usageLineId: id, state: state, observedAt: now, isUncertainNearLimit: uncertainNearLimit)
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

    func beyondReset(_ id: String, approximate: Bool = false) -> AllowanceForecast {
        AllowanceForecast(
            usageLineId: id,
            state: .beyondReset(resetsAt: now.addingTimeInterval(5 * 60 * 60)),
            observedAt: now,
            evidenceSpan: 60 * 60,
            isApproximate: approximate
        )
    }

    func abbreviated(_ interval: TimeInterval) -> String {
        CoarseDurationFormatting.string(from: interval)
    }

    func span(_ interval: TimeInterval) -> String {
        CoarseDurationFormatting.evidenceSpan(interval)
    }
}
