import Core
import XCTest
@testable import ZAIAPIProvider

/// Shared setup for the z.ai API test classes, which stay split to keep each
/// under SwiftLint's type-body-length threshold.
class ZAIAPIProviderTestCase: XCTestCase {
    var provider: ZAIAPIProvider!
    var retryGate: ProviderRetryGate!

    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        retryGate = ProviderRetryGate()
        provider = ZAIAPIProvider(session: URLSession(configuration: config), retryGate: retryGate)
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        MockURLProtocol.reset()
        provider = nil
        retryGate = nil
        super.tearDown()
    }

    func fetch(_ data: Data, baseURL: URL = ZAIAPIProvider.baseURL) async throws -> ProviderQuota {
        MockURLProtocol.responseData = data
        return try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: baseURL)
    }

    func fetch(json: String) async throws -> ProviderQuota {
        try await fetch(Data(json.utf8))
    }

    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }

    func amounts(_ quota: ProviderQuota) -> [UsageBalance.Amount?] {
        quota.lines.map(\.balance?.amount)
    }
}
