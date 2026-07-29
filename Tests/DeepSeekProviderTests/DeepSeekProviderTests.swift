import Core
@testable import DeepSeekProvider
import XCTest

final class DeepSeekProviderTests: XCTestCase {
    private var provider: DeepSeekProvider!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        provider = DeepSeekProvider(session: session)
    }

    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        provider = nil
        session = nil
        super.tearDown()
    }

    private func fetchWithDefaultBaseURL() async throws -> ProviderQuota {
        try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: DeepSeekProvider.baseURL)
    }

    private func fetchWithMock(_ data: Data) async throws -> ProviderQuota {
        MockURLProtocol.responseData = data
        MockURLProtocol.responseStatusCode = 200
        return try await fetchWithDefaultBaseURL()
    }

    // MARK: - Authenticated request

    func testFetchQuota_issuesCorrectRequest() async throws {
        _ = try await fetchWithMock(validResponseJSON())

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testFetchQuota_usesCustomBaseURLWhenProvided() async throws {
        MockURLProtocol.responseData = validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let proxy = try XCTUnwrap(URL(string: "https://deepseek-proxy.example.com"))

        _ = try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: proxy)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://deepseek-proxy.example.com/user/balance")
    }

    // MARK: - Balance maps to currency-tagged UsageLines

    func testFetchQuota_mapsBalanceInfosToLines() async throws {
        let quota = try await fetchWithMock(validResponseJSON())

        XCTAssertEqual(quota.lines.count, 3)
        XCTAssertEqual(quota.lines[0].label, "Total balance")
        XCTAssertEqual(quota.lines[1].label, "Granted credits")
        XCTAssertEqual(quota.lines[2].label, "Topped up")
    }

    func testFetchQuota_parsesStringAmountsToDouble() async throws {
        let quota = try await fetchWithMock(validResponseJSON())

        XCTAssertEqual(try XCTUnwrap(quota.lines[0].total), 110.00, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(quota.lines[1].total), 10.00, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(quota.lines[2].total), 100.00, accuracy: 0.001)
    }

    func testFetchQuota_mapsCreditsAndAvailabilityIntoActivityObservation() async throws {
        let quota = try await fetchWithMock(validResponseJSON())

        XCTAssertEqual(quota.activityObservation?.availability, .available)
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "total-balance-cny", kind: .credits, value: .number(110)),
            ProviderActivityMetric(id: "granted-balance-cny", kind: .credits, value: .number(10)),
            ProviderActivityMetric(id: "topped-up-balance-cny", kind: .credits, value: .number(100)),
        ])
    }

    func testFetchQuota_tagsEachLineWithRawCurrencyCode() async throws {
        let quota = try await fetchWithMock(validResponseJSON())

        for line in quota.lines {
            XCTAssertEqual(line.unit, "CNY")
        }
    }

    func testFetchQuota_supportsUSDCurrency() async throws {
        let quota = try await fetchWithMock(usdResponseJSON())

        XCTAssertEqual(quota.lines.count, 3)
        for line in quota.lines {
            XCTAssertEqual(line.unit, "USD")
        }
    }

    // MARK: - is_available: false surfaced explicitly

    func testFetchQuota_unavailableHeadlineWhenIsAvailableFalse() async throws {
        let json = Data("""
        {
          "is_available": false,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """.utf8)
        let quota = try await fetchWithMock(json)

        XCTAssertEqual(quota.headline, "No balance available")
        // Lines are still returned so the user can see what's left.
        XCTAssertEqual(quota.lines.count, 3)
        XCTAssertEqual(quota.activityObservation?.availability, .unavailable)
    }

    // MARK: - Headline shows total balance, currency-aware

    func testFetchQuota_headlineFormatsTotalBalanceWithCurrencySymbol() async throws {
        let quota = try await fetchWithMock(validResponseJSON())

        // The exact output of NumberFormatter.currency is locale- and OS-
        // dependent. We verify structure: the headline must end with " left"
        // and the amount portion must not be a bare Double description
        // (which would mean the formatter wasn't used).
        XCTAssertTrue(quota.headline.hasSuffix(" left"), "headline was: \(quota.headline)")

        let amountPart = String(quota.headline.dropLast(" left".count))
        XCTAssertNotEqual(
            amountPart, "110.0",
            "currency formatter must be used, not bare Double: \(amountPart)"
        )
    }

    func testFetchQuota_headlineFallsBackToNoDataWhenBalanceInfosEmpty() async throws {
        let json = Data("""
        {
          "is_available": true,
          "balance_infos": []
        }
        """.utf8)
        let quota = try await fetchWithMock(json)

        XCTAssertEqual(quota.headline, "No data")
        XCTAssertEqual(quota.lines.count, 0)
    }

    // MARK: - Failures surface as typed errors

    func testFetchQuota_throwsMissingKeyForEmptyKey() async throws {
        do {
            _ = try await provider.fetchQuota(auth: .apiKey(""), baseURL: DeepSeekProvider.baseURL)
            XCTFail("Expected missingKey error")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .missingKey)
        }
    }

    func testFetchQuota_throwsHttpForNon200Statuses() async throws {
        for code in [401, 429, 500] {
            MockURLProtocol.responseData = Data()
            MockURLProtocol.responseStatusCode = code
            MockURLProtocol.lastRequest = nil

            do {
                _ = try await fetchWithDefaultBaseURL()
                XCTFail("Expected http(\(code)) error")
            } catch let error as DeepSeekError {
                XCTAssertEqual(error, .http(code))
            }
        }
    }

    func testFetchQuota_throwsNetworkForConnectionFailure() async throws {
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        do {
            _ = try await fetchWithDefaultBaseURL()
            XCTFail("Expected network error")
        } catch let error as DeepSeekError {
            if case .network = error {
            } else {
                XCTFail("Expected .network error, got \(error)")
            }
        }
    }

    func testFetchQuota_throwsDecodingForInvalidJSON() async throws {
        MockURLProtocol.responseData = Data("not json".utf8)
        MockURLProtocol.responseStatusCode = 200

        do {
            _ = try await fetchWithDefaultBaseURL()
            XCTFail("Expected decoding error")
        } catch let error as DeepSeekError {
            if case .decoding = error {
            } else {
                XCTFail("Expected .decoding error, got \(error)")
            }
        }
    }

    // MARK: - 401 → localized "Authentication failed"; 429 → "Rate limited"

    func testDeepSeekError_401MapsToAuthenticationFailed() {
        XCTAssertEqual(
            DeepSeekError.http(401).errorDescription,
            "Authentication failed. Check your API key."
        )
    }

    func testDeepSeekError_429MapsToRateLimited() {
        XCTAssertEqual(
            DeepSeekError.http(429).errorDescription,
            "Rate limited. Try again later."
        )
    }

    // MARK: - internal-consistency assertion

    func testFetchQuota_throwsInternalInconsistencyForApiKeyFree() async throws {
        do {
            _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: DeepSeekProvider.baseURL)
            XCTFail("Expected internalInconsistency error")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .internalInconsistency)
        }
    }

    // MARK: - currentSetupState returns nil for .apiKey providers

    func testCurrentSetupState_returnsNil() async {
        let state = await provider.currentSetupState()
        XCTAssertNil(state)
    }

    // MARK: - Helpers

    private func validResponseJSON() -> Data {
        Data("""
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """.utf8)
    }

    private func usdResponseJSON() -> Data {
        Data("""
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "USD",
              "total_balance": "18.50",
              "granted_balance": "0.00",
              "topped_up_balance": "18.50"
            }
          ]
        }
        """.utf8)
    }
}
