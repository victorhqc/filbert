import Core
import Foundation
import XCTest
@testable import ZAIProvider

final class ZAIProviderRetryGateTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseHeaders = nil
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.handler = nil
        MockURLProtocol.capturedRequests = []
        session = nil
        super.tearDown()
    }

    func testRecordsRateLimitDeadlineFromTheQuotaRequest() async throws {
        let provider = makeProvider()
        MockURLProtocol.responseStatusCode = 429
        MockURLProtocol.responseHeaders = ["Retry-After": "120"]

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKey("test-key"),
                baseURL: ZAIProvider.baseURL
            )
            XCTFail("Expected http error")
        } catch let error as ZAIError {
            XCTAssertEqual(error, .http(429))
        }

        XCTAssertEqual(provider.retryGate?.remaining, 120)
    }

    func testSurfacesASubscriptionRateLimit() async throws {
        let provider = makeProvider()
        MockURLProtocol.responseHeaders = ["Retry-After": "90"]
        MockURLProtocol.handler = { request in
            if request.url?.path.contains("monitor") == true {
                return (200, ZAIProviderTests.validResponseJSON())
            }
            return (429, Data())
        }

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKey("test-key"),
                baseURL: ZAIProvider.baseURL
            )
            XCTFail("Expected http error")
        } catch let error as ZAIError {
            XCTAssertEqual(error, .http(429))
        }

        XCTAssertEqual(provider.retryGate?.remaining, 90)
    }

    func testKeepsQuotaWhenSubscriptionMetadataFails() async throws {
        let provider = makeProvider()
        MockURLProtocol.handler = { request in
            if request.url?.path.contains("monitor") == true {
                return (200, ZAIProviderTests.validResponseJSON())
            }
            return (500, Data())
        }

        let quota = try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )

        XCTAssertTrue(quota.headline.hasPrefix("42%"))
        XCTAssertEqual(provider.retryGate?.remaining, 0)
    }

    private func makeProvider() -> ZAIProvider {
        ZAIProvider(
            session: session,
            errorLog: ZAIProviderTests.makeErrorLog(),
            retryGate: ProviderRetryGate(now: { 0 })
        )
    }
}
