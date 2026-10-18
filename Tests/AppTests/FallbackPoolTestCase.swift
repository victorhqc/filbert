@testable import App
import Core
import XCTest

class FallbackPoolTestCase: XCTestCase {
    let providerId = "openai-codex"
    let now = Date(timeIntervalSince1970: 1_791_838_000)
    var fiveHourReset: Date {
        now.addingTimeInterval(2 * 60 * 60)
    }

    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        super.tearDown()
    }

    func quota(
        fiveHour: Double,
        weekly: Double = 66,
        credits: Decimal?,
        declaresFallback: Bool = true,
        isStale: Bool = false
    ) -> ProviderQuota {
        let balance = credits.map { UsageBalance(amount: .finite($0), unit: .credits) }
        return quota(
            fiveHour: fiveHour,
            weekly: weekly,
            creditsLine: balance.map { creditsLine(balance: $0, declaresFallback: declaresFallback) },
            isStale: isStale
        )
    }

    func quota(fiveHour: Double, weekly: Double = 66, creditsLine: UsageLine?, isStale: Bool = false) -> ProviderQuota {
        let lines = [
            UsageLine(
                label: DisplayText(verbatim: "5-hour window"),
                percentage: fiveHour,
                resetDate: fiveHourReset,
                id: "five-hour",
                limitGroup: "subscription"
            ),
            UsageLine(
                label: DisplayText(verbatim: "Weekly"),
                percentage: weekly,
                id: "weekly",
                limitGroup: "subscription"
            ),
        ] + [creditsLine].compactMap(\.self)
        return ProviderQuota(
            providerId: providerId,
            providerName: "OpenAI Codex",
            headline: DisplayText(verbatim: "\(Int(fiveHour))% · resets in 2 hours"),
            lines: lines,
            lastUpdated: now,
            isStale: isStale,
            headlineUsageLineId: "five-hour"
        )
    }

    func creditsLine(
        balance: UsageBalance?,
        details: [UsageDetail]? = nil,
        declaresFallback: Bool = true
    ) -> UsageLine {
        UsageLine(
            label: DisplayText(verbatim: "Credits"),
            balance: balance,
            details: details,
            id: "credits",
            fallbackForLimitGroup: declaresFallback ? "subscription" : nil
        )
    }

    func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
