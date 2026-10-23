import Core
@testable import KimiCodeProvider
import XCTest

/// Shared setup for the Kimi Code test classes, which stay split to keep each
/// under SwiftLint's type-body-length threshold.
class KimiCodeProviderTestCase: XCTestCase {
    var provider: KimiCodeProvider!
    var retryGate: ProviderRetryGate!

    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        retryGate = ProviderRetryGate()
        provider = KimiCodeProvider(session: URLSession(configuration: config), retryGate: retryGate)
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        MockURLProtocol.reset()
        provider = nil
        retryGate = nil
        super.tearDown()
    }

    func fetch(_ data: Data, baseURL: URL = KimiCodeProvider.baseURL) async throws -> ProviderQuota {
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

    func date(_ text: String) throws -> Date {
        try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
    }

    func assertPercentages(
        _ quota: ProviderQuota,
        _ expected: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = quota.lines.map { $0.percentage ?? .nan }
        XCTAssertEqual(actual.count, expected.count, "\(actual)", file: file, line: line)
        for (value, expectedValue) in zip(actual, expected) {
            XCTAssertEqual(value, expectedValue, accuracy: 0.0001, "\(actual)", file: file, line: line)
        }
    }
}
