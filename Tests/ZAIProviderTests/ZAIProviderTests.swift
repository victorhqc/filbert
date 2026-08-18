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
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.handler = nil
        MockURLProtocol.capturedRequests = []
        provider = nil
        session = nil
        super.tearDown()
    }

    // MARK: - Authenticated requests

    func testFetchQuota_issuesCorrectRequests() async throws {
        MockURLProtocol.handler = { _ in
            (200, Self.validResponseJSON())
        }

        _ = try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )

        let requests = MockURLProtocol.capturedRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.map { $0.url?.path },
            ["/api/monitor/usage/quota/limit", "/api/biz/subscription/list"]
        )
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            // z.ai expects the raw token with no "Bearer " prefix.
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        }
    }

    // MARK: - custom base URL (proxy) is honored

    func testFetchQuota_usesCustomBaseURLWhenProvided() async throws {
        MockURLProtocol.handler = { _ in
            (200, Self.validResponseJSON())
        }

        let proxy = try XCTUnwrap(URL(string: "https://proxy.example.com"))

        _ = try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: proxy
        )

        let firstRequest = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(firstRequest.url?.absoluteString, "https://proxy.example.com/api/monitor/usage/quota/limit")
        XCTAssertEqual(
            MockURLProtocol.capturedRequests.last?.url?.absoluteString,
            "https://proxy.example.com/api/biz/subscription/list"
        )
    }

    // MARK: - nextResetTime → resetDate

    func testFetchQuota_convertsEpochMsToDate() async throws {
        MockURLProtocol.responseData = Self.validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )
        let fiveHour = quota.lines[0]

        XCTAssertNotNil(fiveHour.resetDate)
        let expected = Date(timeIntervalSince1970: 1_713_127_600)
        let resetDate = try XCTUnwrap(fiveHour.resetDate)
        XCTAssertEqual(resetDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Headline priority (5-hour → weekly)

    func testFetchQuota_headlineUsesFiveHourPriority() async throws {
        MockURLProtocol.responseData = Self.validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )

        XCTAssertTrue(quota.headline.hasPrefix("42%"))
        XCTAssertTrue(quota.headline.contains("·"))
    }

    func testFetchQuota_headlineFallsBackToWeekly() async throws {
        let json = Data("""
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 6, "percentage": 75, "nextResetTime": 1713127600000}
            ]
          }
        }
        """.utf8)

        MockURLProtocol.responseData = json
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )

        XCTAssertTrue(quota.headline.hasPrefix("75%"))
        XCTAssertTrue(quota.headline.contains("·"))
    }

    func testFetchQuota_headlineNoDataWhenNoRecognizedLimits() async throws {
        let json = Data("""
        {
          "data": {
            "limits": []
          }
        }
        """.utf8)

        MockURLProtocol.responseData = json
        MockURLProtocol.responseStatusCode = 200

        let quota = try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )
        XCTAssertEqual(quota.headline, "No data")
    }

    // MARK: - Failures surface as typed errors

    func testFetchQuota_throwsMissingKeyForEmptyKey() async throws {
        do {
            _ = try await provider.fetchQuota(
                auth: .apiKey(""),
                baseURL: ZAIProvider.baseURL
            )
            XCTFail("Expected missingKey error")
        } catch let error as ZAIError {
            XCTAssertEqual(error, .missingKey)
        }
    }

    func testFetchQuota_throwsHttpForNon200() async throws {
        MockURLProtocol.responseData = Data()
        MockURLProtocol.responseStatusCode = 401

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKey("test-key"),
                baseURL: ZAIProvider.baseURL
            )
            XCTFail("Expected http error")
        } catch let error as ZAIError {
            XCTAssertEqual(error, .http(401))
        }
    }

    func testFetchQuota_throwsNetworkForConnectionFailure() async throws {
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKey("test-key"),
                baseURL: ZAIProvider.baseURL
            )
            XCTFail("Expected network error")
        } catch let error as ZAIError {
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
            _ = try await provider.fetchQuota(
                auth: .apiKey("test-key"),
                baseURL: ZAIProvider.baseURL
            )
            XCTFail("Expected decoding error")
        } catch let error as ZAIError {
            if case .decoding = error {
            } else {
                XCTFail("Expected .decoding error, got \(error)")
            }
        }
    }

    // MARK: - internal-consistency assertion

    func testFetchQuota_throwsInternalInconsistencyForApiKeyFree() async throws {
        MockURLProtocol.responseData = Self.validResponseJSON()
        MockURLProtocol.responseStatusCode = 200

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: ZAIProvider.baseURL
            )
            XCTFail("Expected internalInconsistency error")
        } catch let error as ZAIError {
            XCTAssertEqual(error, .internalInconsistency)
        }
    }

    // MARK: - currentSetupState returns nil for .apiKey providers

    func testCurrentSetupState_returnsNil() async {
        let state = await provider.currentSetupState()
        XCTAssertNil(state)
    }

    // MARK: - Helpers

    private static func validResponseJSON() -> Data {
        Data("""
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
        """.utf8)
    }
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    static var responseData: Data?
    static var responseStatusCode = 200
    static var responseError: Error?
    static var lastRequest: URLRequest?
    static var capturedRequests: [URLRequest] = []
    static var handler: ((URLRequest) -> (statusCode: Int, data: Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)
        MockURLProtocol.lastRequest = request

        if let error = MockURLProtocol.responseError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let statusCode: Int
        let data: Data
        if let handler = MockURLProtocol.handler {
            (statusCode, data) = handler(request)
        } else {
            statusCode = MockURLProtocol.responseStatusCode
            data = MockURLProtocol.responseData ?? Data()
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
