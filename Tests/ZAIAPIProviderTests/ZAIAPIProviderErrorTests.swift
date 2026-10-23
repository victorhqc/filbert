import Core
import XCTest
@testable import ZAIAPIProvider

final class ZAIAPIProviderErrorTests: ZAIAPIProviderTestCase {
    private let authenticationFailed = "Authentication failed. Check your API key. "
        + "Keys from bigmodel.cn need the base URL https://open.bigmodel.cn."

    func testEmptyKeyThrowsMissingKey() async {
        await assertFetch(auth: .apiKey(""), throws: .missingKey)
        XCTAssertNil(MockURLProtocol.lastRequest)
    }

    func testKeyFreeAuthIsAnInternalInconsistency() async {
        await assertFetch(auth: .apiKeyFree, throws: .internalInconsistency)
    }

    // MARK: - Envelopes

    func testLiveBadKeyEnvelopeIsAnAuthenticationFailure() async throws {
        MockURLProtocol.responseData = try fixture("envelope-bad-key")

        await assertFetch(throws: .rejected(code: 401))
        XCTAssertEqual(ZAIAPIError.rejected(code: 401).errorDescription, authenticationFailed)
    }

    func testLiveMissingKeyEnvelopeIsAnAuthenticationFailure() async throws {
        MockURLProtocol.responseData = try fixture("envelope-missing-key")

        await assertFetch(throws: .rejected(code: 1001))
        XCTAssertEqual(ZAIAPIError.rejected(code: 1001).errorDescription, authenticationFailed)
    }

    func testMonitorAuthenticationCodesAreAuthenticationFailures() {
        for code in [1000, 1002] {
            XCTAssertEqual(ZAIAPIError.rejected(code: code).errorDescription, authenticationFailed, "\(code)")
        }
    }

    func testLiveUnknownRouteEnvelopeReturnsNoBalance() async throws {
        MockURLProtocol.responseData = try fixture("envelope-unknown-route")

        await assertFetch(throws: .rejected(code: 404))
        XCTAssertEqual(
            ZAIAPIError.rejected(code: 404).errorDescription,
            "z.ai did not return a balance for this key."
        )
    }

    func testSuccessNeedsTheFlagTheCodeAndTheData() async {
        let bodies = [
            #"{"code":200,"msg":"","data":{"balance":1},"success":false}"#,
            #"{"code":200,"msg":"","data":{"balance":1}}"#,
            #"{"code":200,"msg":"","data":null,"success":true}"#,
            #"{"code":0,"msg":"","data":{"balance":1},"success":true}"#,
        ]
        for body in bodies {
            MockURLProtocol.responseData = Data(body.utf8)

            do {
                _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: ZAIAPIProvider.baseURL)
                XCTFail("Expected a rejection for \(body)")
            } catch let error as ZAIAPIError {
                guard case .rejected = error else {
                    return XCTFail("Expected a rejection for \(body), got \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - HTTP

    func testUnauthorizedStatusIsAnAuthenticationFailure() async {
        MockURLProtocol.responseStatusCode = 401

        await assertFetch(throws: .http(401))
        XCTAssertEqual(ZAIAPIError.http(401).errorDescription, authenticationFailed)
    }

    func testRateLimitRecordsTheRetryDeadline() async {
        MockURLProtocol.responseStatusCode = 429
        MockURLProtocol.responseHeaders = ["Retry-After": "120"]

        await assertFetch(throws: .http(429))
        XCTAssertEqual(retryGate.remaining, 120, accuracy: 1)
        XCTAssertEqual(ZAIAPIError.http(429).errorDescription, "Rate limited. Try again later.")
    }

    func testServerErrorIsUnexpected() async {
        MockURLProtocol.responseStatusCode = 500

        await assertFetch(throws: .http(500))
        XCTAssertEqual(retryGate.remaining, 0)
        XCTAssertEqual(ZAIAPIError.http(500).errorDescription, "Unexpected response from server.")
    }

    func testUndecodableBodyIsADecodingError() async {
        for body in ["not json", #"{"msg":"no code"}"#] {
            MockURLProtocol.responseData = Data(body.utf8)

            do {
                _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: ZAIAPIProvider.baseURL)
                XCTFail("Expected a decoding error for \(body)")
            } catch let ZAIAPIError.decoding(error) {
                XCTAssertNotNil(ZAIAPIError.decoding(error).underlyingError)
                XCTAssertEqual(ZAIAPIError.decoding(error).errorDescription, "Unexpected response from server.")
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testNetworkFailureIsANetworkError() async {
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        do {
            _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: ZAIAPIProvider.baseURL)
            XCTFail("Expected a network error")
        } catch let error as ZAIAPIError {
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
        throws expected: ZAIAPIError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await provider.fetchQuota(auth: auth, baseURL: ZAIAPIProvider.baseURL)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ZAIAPIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
