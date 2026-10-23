import Core
@testable import KimiAPIProvider
import XCTest

final class KimiAPIProviderErrorTests: XCTestCase {
    private var provider: KimiAPIProvider!
    private var retryGate: ProviderRetryGate!

    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        retryGate = ProviderRetryGate()
        provider = KimiAPIProvider(session: URLSession(configuration: config), retryGate: retryGate)
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        MockURLProtocol.reset()
        provider = nil
        retryGate = nil
        super.tearDown()
    }

    func testEmptyKeyThrowsMissingKey() async {
        await assertFetch(auth: .apiKey(""), throws: .missingKey)
        XCTAssertNil(MockURLProtocol.lastRequest)
    }

    func testKeyFreeAuthIsAnInternalInconsistency() async {
        await assertFetch(auth: .apiKeyFree, throws: .internalInconsistency)
    }

    func testLiveUnauthorizedBodyNamesTheChinaBaseURL() async throws {
        MockURLProtocol.responseStatusCode = 401
        MockURLProtocol.responseData = try fixture("unauthorized-live")

        await assertFetch(throws: .http(401))
        XCTAssertEqual(
            KimiAPIError.http(401).errorDescription,
            "Authentication failed. Check your API key. "
                + "Keys from platform.kimi.com need the base URL https://api.moonshot.cn."
        )
    }

    func testRateLimitRecordsTheRetryDeadline() async {
        MockURLProtocol.responseStatusCode = 429
        MockURLProtocol.responseHeaders = ["Retry-After": "120"]

        await assertFetch(throws: .http(429))
        XCTAssertEqual(retryGate.remaining, 120, accuracy: 1)
        XCTAssertEqual(KimiAPIError.http(429).errorDescription, "Rate limited. Try again later.")
    }

    func testServerErrorIsUnexpected() async {
        MockURLProtocol.responseStatusCode = 500

        await assertFetch(throws: .http(500))
        XCTAssertEqual(retryGate.remaining, 0)
        XCTAssertEqual(KimiAPIError.http(500).errorDescription, "Unexpected response from server.")
    }

    func testNonZeroCodeIsRejected() async {
        MockURLProtocol.responseData = Data(#"{"code":5,"data":null,"scode":"0x5","status":false}"#.utf8)

        await assertFetch(throws: .rejected(code: 5))
        XCTAssertEqual(KimiAPIError.rejected(code: 5).errorDescription, "Unexpected response from server.")
    }

    func testFalseStatusIsRejected() async {
        MockURLProtocol.responseData = Data(#"""
        {"code":0,"data":{"available_balance":1,"voucher_balance":0,"cash_balance":1},"scode":"0x0","status":false}
        """#.utf8)

        await assertFetch(throws: .rejected(code: 0))
    }

    func testMissingDataIsRejected() async {
        MockURLProtocol.responseData = Data(#"{"code":0,"scode":"0x0","status":true}"#.utf8)

        await assertFetch(throws: .rejected(code: 0))
    }

    func testUndecodableBodyIsADecodingError() async {
        MockURLProtocol.responseData = Data("not json".utf8)

        do {
            _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: KimiAPIProvider.baseURL)
            XCTFail("Expected a decoding error")
        } catch let KimiAPIError.decoding(error) {
            XCTAssertNotNil(KimiAPIError.decoding(error).underlyingError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkFailureIsANetworkError() async {
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        do {
            _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: KimiAPIProvider.baseURL)
            XCTFail("Expected a network error")
        } catch let error as KimiAPIError {
            guard case .network = error else {
                return XCTFail("Expected a network error, got \(error)")
            }
            XCTAssertTrue(isConnectivityError(error))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func assertFetch(
        auth: ProviderAuth = .apiKey("test-key"),
        throws expected: KimiAPIError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await provider.fetchQuota(auth: auth, baseURL: KimiAPIProvider.baseURL)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as KimiAPIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
