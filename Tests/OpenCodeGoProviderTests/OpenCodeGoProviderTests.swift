import Core
@testable import OpenCodeGoProvider
import XCTest

final class OpenCodeGoProviderTests: XCTestCase {
    private var provider: OpenCodeGoProvider!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        provider = OpenCodeGoProvider(session: session)
    }

    override func tearDown() {
        MockURLProtocol.responseData = Data()
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.requestCount = 0
        provider = nil
        session = nil
        super.tearDown()
    }

    func testFetchQuota_issuesOneAuthenticatedRequest() async throws {
        MockURLProtocol.responseData = fixture(named: "usage-success")

        _ = try await fetchQuota()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testFetchQuota_rejectsUntrustedBaseURLBeforeSendingKey() async throws {
        let proxy = try XCTUnwrap(URL(string: "https://proxy.example.com"))

        await assertThrowsOpenCodeGoError(.untrustedBaseURL) {
            _ = try await self.provider.fetchQuota(auth: .apiKey("test-key"), baseURL: proxy)
        }

        XCTAssertNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
    }

    func testFetchQuota_mapsServerUsageWindows() async throws {
        MockURLProtocol.responseData = fixture(named: "usage-success")

        let quota = try await fetchQuota()

        XCTAssertEqual(quota.providerId, "opencode-go")
        XCTAssertEqual(quota.providerName, "OpenCode Go")
        XCTAssertEqual(quota.headline, "OpenCode Go usage")
        XCTAssertEqual(quota.lines.map(\.label), ["5-hour window", "Weekly", "Monthly"])
        XCTAssertEqual(quota.lines.map(\.percentage), [2, 1, 0])
        XCTAssertEqual(quota.lines[0].resetDate, date("2026-08-15T03:20:21.283Z"))
        XCTAssertEqual(quota.lines[1].resetDate, date("2026-08-18T00:00:00.000Z"))
        XCTAssertEqual(quota.lines[2].resetDate, date("2026-09-01T00:00:00.000Z"))
        XCTAssertEqual(quota.lines[0].windowDuration, UsageWindowDuration.fiveHours)
        XCTAssertEqual(quota.lines[1].windowDuration, UsageWindowDuration.week)
        XCTAssertEqual(quota.lines[2].windowDuration, UsageWindowDuration.month)
        XCTAssertTrue(quota.lines.allSatisfy { $0.used == nil && $0.total == nil && $0.unit == nil })
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "rolling-window-usage", kind: .usage, value: .number(2)),
            ProviderActivityMetric(id: "weekly-window-usage", kind: .usage, value: .number(1)),
            ProviderActivityMetric(id: "monthly-window-usage", kind: .usage, value: .number(0)),
        ])
    }

    func testFetchQuota_surfacesRateLimitedWindowStatus() async throws {
        MockURLProtocol.responseData = fixture(named: "rate-limited-usage")

        let quota = try await fetchQuota()

        let details = try XCTUnwrap(quota.lines[0].details)
        XCTAssertEqual(details.count, 1)
        XCTAssertEqual(details[0].label, "Status")
        XCTAssertEqual(details[0].value, "Rate limited")
    }

    func testFetchQuota_throwsMissingKey() async {
        await assertThrowsOpenCodeGoError(.missingKey) {
            _ = try await self.provider.fetchQuota(
                auth: .apiKey(""),
                baseURL: OpenCodeGoProvider.baseURL
            )
        }
    }

    func testFetchQuota_throwsAuthenticationFailedFor401Fixture() async {
        MockURLProtocol.responseData = fixture(named: "auth-error")
        MockURLProtocol.responseStatusCode = 401

        await assertThrowsOpenCodeGoError(.authenticationFailed) {
            _ = try await self.fetchQuota()
        }
    }

    func testFetchQuota_throwsNoSubscriptionFor403Fixture() async {
        MockURLProtocol.responseData = fixture(named: "entitlement-error")
        MockURLProtocol.responseStatusCode = 403

        await assertThrowsOpenCodeGoError(.noSubscription) {
            _ = try await self.fetchQuota()
        }
    }

    func testFetchQuota_throwsRateLimitedAndBacksOffAfter429() async {
        MockURLProtocol.responseStatusCode = 429

        await assertThrowsOpenCodeGoError(.rateLimited) {
            _ = try await self.fetchQuota()
        }
        await assertThrowsOpenCodeGoError(.rateLimited) {
            _ = try await self.fetchQuota()
        }

        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testFetchQuota_throwsTypedErrorForPayloadDriftFixture() async {
        MockURLProtocol.responseData = fixture(named: "payload-drift")

        do {
            _ = try await fetchQuota()
            XCTFail("Expected decoding error")
        } catch let error as OpenCodeGoError {
            guard case .decoding = error else {
                return XCTFail("Expected decoding error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchQuota_throwsNetworkError() async {
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        do {
            _ = try await fetchQuota()
            XCTFail("Expected network error")
        } catch let error as OpenCodeGoError {
            guard case .network = error else {
                return XCTFail("Expected network error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchQuota_throwsInternalInconsistencyForApiKeyFree() async {
        await assertThrowsOpenCodeGoError(.internalInconsistency) {
            _ = try await self.provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: OpenCodeGoProvider.baseURL
            )
        }
    }

    func testOpenCodeGoError_hasDistinctAuthenticationAndEntitlementMessages() {
        XCTAssertEqual(
            OpenCodeGoError.authenticationFailed.errorDescription,
            "Authentication failed. Check your API key."
        )
        XCTAssertEqual(OpenCodeGoError.noSubscription.errorDescription, "No OpenCode Go subscription.")
    }

    func testCurrentSetupState_returnsNil() async {
        let setupState = await provider.currentSetupState()
        XCTAssertNil(setupState)
    }

    private func fetchQuota() async throws -> ProviderQuota {
        try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: OpenCodeGoProvider.baseURL)
    }

    private func fixture(named name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }

    private func assertThrowsOpenCodeGoError(
        _ expected: OpenCodeGoError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as OpenCodeGoError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
