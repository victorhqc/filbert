import Core
import Foundation

struct ZAIProvider: AIProvider {
    static let providerId = "zai"
    static let providerName = "z.ai"

    func fetchQuota(apiKey: String) async throws -> ProviderQuota {
        _ = apiKey // unused in stub; real integration in later spec (core 01)
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "42% · resets in 3h",
            lines: [
                UsageLine(
                    label: "5-hour window",
                    used: 420,
                    total: 1000,
                    percentage: 42,
                    unit: "requests",
                    resetDate: Date().addingTimeInterval(3 * 3600),
                    details: nil
                ),
            ],
            lastUpdated: Date(),
            error: nil
        )
    }
}
