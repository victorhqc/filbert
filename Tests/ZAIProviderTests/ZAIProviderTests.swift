import Core
import XCTest

@testable import ZAIProvider

final class ZAIProviderTests: XCTestCase {
    private var provider: ZAIProvider!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        provider = ZAIProvider(session: session)
    }

    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        provider = nil
        session = nil
        super.tearDown()
    }

    // MARK: - AC1: Authenticated request

    func testFetchQuota_issuesCorrectRequest() async throws {
        MockURLProtocol.responseData = validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        _ = try await provider.fetchQuota(apiKey: "test-key")

        let request = MockURLProtocol.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://api.z.ai/api/monitor/usage/quota/limit")
        XCTAssertEqual(request?.httpMethod, "GET")
        // z.ai expects the raw token with no "Bearer " prefix.
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "test-key")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    // MARK: - AC2: Known (type, unit) → labelled UsageLine

    func testFetchQuota_mapsKnownTypeUnitPairs() async throws {
        MockURLProtocol.responseData = validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")

        XCTAssertEqual(quota.lines.count, 3)
        XCTAssertEqual(quota.lines[0].label, "5-hour window")
        XCTAssertEqual(quota.lines[1].label, "Weekly")
        XCTAssertEqual(quota.lines[2].label, "Monthly web-tool calls")
    }

    func testFetchQuota_mapsPercentageAndUsage() async throws {
        MockURLProtocol.responseData = validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")
        let fiveHour = quota.lines[0]

        XCTAssertEqual(fiveHour.percentage, 42)
        XCTAssertEqual(fiveHour.used, 420)
    }

    /// z.ai's monthly web-tool line carries `currentValue` (actual used) and
    /// `usage` (the allowance/cap). `currentValue` must map to `used` and
    /// `usage` to `total` — not the reverse.
    func testFetchQuota_currentValueIsUsedAndUsageIsTotal() async throws {
        let json = """
        {
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "percentage": 0,
                "usage": 1000,
                "currentValue": 0,
                "remaining": 1000
              }
            ]
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.responseData = json
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")
        let monthly = quota.lines[0]
        XCTAssertEqual(monthly.used, 0)
        XCTAssertEqual(monthly.total, 1000)
    }

    func testFetchQuota_ignoresUnknownTypeUnitPairs() async throws {
        let json = """
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 3, "percentage": 50},
              {"type": "UNKNOWN_TYPE", "unit": 99, "percentage": 99}
            ]
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.responseData = json
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")
        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].label, "5-hour window")
    }

    // MARK: - AC3: nextResetTime → resetDate

    func testFetchQuota_convertsEpochMsToDate() async throws {
        MockURLProtocol.responseData = validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")
        let fiveHour = quota.lines[0]

        XCTAssertNotNil(fiveHour.resetDate)
        let expected = Date(timeIntervalSince1970: 1_713_127_600)
        XCTAssertEqual(fiveHour.resetDate!.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - AC4: usageDetails → UsageDetail rows

    func testFetchQuota_mapsUsageDetails() async throws {
        MockURLProtocol.responseData = validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")
        let fiveHour = quota.lines[0]

        XCTAssertNotNil(fiveHour.details)
        XCTAssertEqual(fiveHour.details?.count, 1)
        XCTAssertEqual(fiveHour.details?[0].label, "deepseek-v3")
        XCTAssertEqual(fiveHour.details?[0].value, "200")
    }

    func testFetchQuota_nilDetailsWhenAbsent() async throws {
        let json = """
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 3, "percentage": 50}
            ]
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.responseData = json
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")
        XCTAssertNil(quota.lines[0].details)
    }

    // MARK: - AC5: Headline priority (5-hour → weekly)

    func testFetchQuota_headlineUsesFiveHourPriority() async throws {
        MockURLProtocol.responseData = validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")

        XCTAssertTrue(quota.headline.hasPrefix("42%"))
        XCTAssertTrue(quota.headline.contains("·"))
    }

    func testFetchQuota_headlineFallsBackToWeekly() async throws {
        let json = """
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 6, "percentage": 75, "nextResetTime": 1713127600000}
            ]
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.responseData = json
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")

        XCTAssertTrue(quota.headline.hasPrefix("75%"))
        XCTAssertTrue(quota.headline.contains("·"))
    }

    func testFetchQuota_headlineNoDataWhenNoRecognizedLimits() async throws {
        let json = """
        {
          "data": {
            "limits": []
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.responseData = json
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(apiKey: "test-key")
        XCTAssertEqual(quota.headline, "No data")
    }

    // MARK: - AC6: Failures surface as typed errors

    func testFetchQuota_throwsMissingKeyForEmptyKey() async throws {
        do {
            _ = try await provider.fetchQuota(apiKey: "")
            XCTFail("Expected missingKey error")
        } catch let error as ZAIError {
            XCTAssertEqual(error, .missingKey)
        }
    }

    func testFetchQuota_throwsHttpForNon200() async throws {
        MockURLProtocol.responseData = Data()
        MockURLProtocol.responseStatusCode = 401

        do {
            _ = try await provider.fetchQuota(apiKey: "test-key")
            XCTFail("Expected http error")
        } catch let error as ZAIError {
            XCTAssertEqual(error, .http(401))
        }
    }

    func testFetchQuota_throwsNetworkForConnectionFailure() async throws {
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        do {
            _ = try await provider.fetchQuota(apiKey: "test-key")
            XCTFail("Expected network error")
        } catch let error as ZAIError {
            if case .network = error {
                // expected
            } else {
                XCTFail("Expected .network error, got \(error)")
            }
        }
    }

    func testFetchQuota_throwsDecodingForInvalidJSON() async throws {
        MockURLProtocol.responseData = "not json".data(using: .utf8)!
        MockURLProtocol.responseStatusCode = 200

        do {
            _ = try await provider.fetchQuota(apiKey: "test-key")
            XCTFail("Expected decoding error")
        } catch let error as ZAIError {
            if case .decoding = error {
                // expected
            } else {
                XCTFail("Expected .decoding error, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func validResponseJSON() -> Data {
        """
        {
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "percentage": 42,
                "usage": 420,
                "nextResetTime": 1713127600000,
                "usageDetails": [
                  {"modelCode": "deepseek-v3", "usage": 200}
                ]
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "percentage": 60,
                "usage": 600,
                "nextResetTime": 1713127600000
              },
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "percentage": 30,
                "usage": 15
              }
            ]
          }
        }
        """.data(using: .utf8)!
    }
}

// MARK: - Mock URLProtocol

private final class MockURLProtocol: URLProtocol {
    static var responseData: Data?
    static var responseStatusCode = 200
    static var responseError: Error?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request

        if let error = MockURLProtocol.responseError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if let data = MockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
