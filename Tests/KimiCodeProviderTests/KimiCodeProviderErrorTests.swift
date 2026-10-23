import Core
@testable import KimiCodeProvider
import XCTest

final class KimiCodeProviderErrorTests: KimiCodeProviderTestCase {
    func testEmptyKeyThrowsMissingKey() async {
        await assertFetch(auth: .apiKey(""), throws: .missingKey)
        XCTAssertNil(MockURLProtocol.lastRequest)
    }

    func testKeyFreeAuthIsAnInternalInconsistency() async {
        await assertFetch(auth: .apiKeyFree, throws: .internalInconsistency)
    }

    func testUnauthorizedNamesTheChinaBaseURL() async {
        MockURLProtocol.responseStatusCode = 401

        await assertFetch(throws: .http(401))
        XCTAssertEqual(
            KimiCodeError.http(401).errorDescription,
            "Authentication failed. Check your Kimi Code API key. "
                + "Accounts in mainland China need the base URL https://api.kimi.com."
        )
    }

    func testForbiddenPointsToTheMembership() async {
        MockURLProtocol.responseStatusCode = 403
        MockURLProtocol.responseData = Data(#"{"error":{"message":"permission denied"}}"#.utf8)

        await assertFetch(throws: .http(403))
        XCTAssertEqual(
            KimiCodeError.http(403).errorDescription,
            "No Kimi Code access. Check your Kimi membership."
        )
    }

    func testRateLimitRecordsTheRetryDeadline() async {
        MockURLProtocol.responseStatusCode = 429
        MockURLProtocol.responseHeaders = ["Retry-After": "120"]

        await assertFetch(throws: .http(429))
        XCTAssertEqual(retryGate.remaining, 120, accuracy: 1)
        XCTAssertEqual(KimiCodeError.http(429).errorDescription, "Rate limited. Try again later.")
    }

    func testServerErrorIsUnexpected() async {
        MockURLProtocol.responseStatusCode = 500

        await assertFetch(throws: .http(500))
        XCTAssertEqual(retryGate.remaining, 0)
        XCTAssertEqual(KimiCodeError.http(500).errorDescription, "Unexpected response from server.")
    }

    func testNonObjectBodyIsADecodingError() async {
        for body in ["[]", "not json"] {
            MockURLProtocol.responseData = Data(body.utf8)

            do {
                _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: KimiCodeProvider.baseURL)
                XCTFail("Expected a decoding error for \(body)")
            } catch let KimiCodeError.decoding(error) {
                XCTAssertNotNil(KimiCodeError.decoding(error).underlyingError)
                XCTAssertEqual(KimiCodeError.decoding(error).errorDescription, "Unexpected response from server.")
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testNetworkFailureIsANetworkError() async {
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        do {
            _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: KimiCodeProvider.baseURL)
            XCTFail("Expected a network error")
        } catch let error as KimiCodeError {
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
        throws expected: KimiCodeError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await provider.fetchQuota(auth: auth, baseURL: KimiCodeProvider.baseURL)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as KimiCodeError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
