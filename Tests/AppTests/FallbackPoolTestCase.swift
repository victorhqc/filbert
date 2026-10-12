@testable import App
import Core
import XCTest

class FallbackPoolTestCase: XCTestCase {
    let providerId = "openai-codex"
    let now = Date(timeIntervalSince1970: 1_791_838_000)
    var fiveHourReset: Date {
        now.addingTimeInterval(2 * 60 * 60)
    }

    func quota(
        fiveHour: Double,
        weekly: Double = 66,
        credits: Decimal?,
        declaresFallback: Bool = true,
        freshness: ProviderActivityFreshness = .fresh,
        isStale: Bool = false
    ) -> ProviderQuota {
        var lines = [
            UsageLine(
                label: "5-hour window",
                percentage: fiveHour,
                resetDate: fiveHourReset,
                id: "five-hour",
                limitGroup: "subscription"
            ),
            UsageLine(label: "Weekly", percentage: weekly, id: "weekly", limitGroup: "subscription"),
        ]
        if let credits {
            lines.append(UsageLine(
                label: "Credits",
                balance: UsageBalance(amount: .finite(credits), unit: .credits),
                id: "credits",
                fallbackForLimitGroup: declaresFallback ? "subscription" : nil
            ))
        }
        return ProviderQuota(
            providerId: providerId,
            providerName: "OpenAI Codex",
            headline: "\(Int(fiveHour))% · resets in 2 hours",
            lines: lines,
            lastUpdated: now,
            isStale: isStale,
            activityObservation: ProviderActivityObservation(freshness: freshness),
            headlineUsageLineId: "five-hour"
        )
    }

    func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
