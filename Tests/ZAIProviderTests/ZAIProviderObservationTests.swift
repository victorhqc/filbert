import Core
import Foundation
import XCTest
@testable import ZAIProvider

final class ZAIProviderObservationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.handler = nil
        MockURLProtocol.capturedRequests = []
        super.tearDown()
    }

    func testFetchQuota_creditAllowanceIsNotConsumption() async throws {
        serve(
            quotaData: Self.creditQuotaJSON(allowance: 100_000, currentValue: 1000, percentage: 1),
            subscriptionJSON: Self.subscriptionJSON(version: "V2")
        )

        let quota = try await fetchQuota()

        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(1)),
            ProviderActivityMetric(id: "five-hour-usage-absolute", kind: .usage, value: .number(1000)),
        ])
    }

    func testFetchQuota_creditShapeWithoutCurrentValueUsesPercentage() async throws {
        let quotaJSON = Data("""
        {
          "data": {
            "limits": [
              {"type": "CREDIT_LIMIT", "unit": 6, "number": 1,
               "usage": 10000, "remaining": 9900, "percentage": 1}
            ]
          }
        }
        """.utf8)
        serve(quotaData: quotaJSON, subscriptionJSON: Self.subscriptionJSON(version: "V2"))

        let quota = try await fetchQuota()

        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "weekly-usage", kind: .usage, value: .number(1)),
        ])
    }

    func testFetchQuota_smallCreditChangeUnderLargeAllowanceIsDetected() async throws {
        serve(
            quotaData: Self.creditQuotaJSON(allowance: 100_000, currentValue: 1000, percentage: 1),
            subscriptionJSON: Self.subscriptionJSON(version: "V2")
        )
        let baseline = try await fetchQuota()

        serve(
            quotaData: Self.creditQuotaJSON(allowance: 100_000, currentValue: 1001, percentage: 1),
            subscriptionJSON: Self.subscriptionJSON(version: "V2")
        )
        let advanced = try await fetchQuota()

        XCTAssertEqual(baseline.lines.map(\.percentage), advanced.lines.map(\.percentage))
        XCTAssertEqual(advanced.activityObservation?.metrics, [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(1)),
            ProviderActivityMetric(id: "five-hour-usage-absolute", kind: .usage, value: .number(1001)),
        ])
        XCTAssertNotEqual(baseline.activityObservation, advanced.activityObservation)
    }

    func testFetchQuota_rawToPercentageOnlyToRawDoesNotReportActivity() async throws {
        serve(
            quotaData: Self.creditQuotaJSON(allowance: 100_000, currentValue: 1000, percentage: 1),
            subscriptionJSON: Self.subscriptionJSON(version: "V2")
        )
        let raw = try await fetchQuota()

        serve(
            quotaData: Self.percentageOnlyQuotaJSON(percentage: 1),
            subscriptionJSON: Self.subscriptionJSON(version: "V2")
        )
        let percentageOnly = try await fetchQuota()

        serve(
            quotaData: Self.creditQuotaJSON(allowance: 100_000, currentValue: 1000, percentage: 1),
            subscriptionJSON: Self.subscriptionJSON(version: "V2")
        )
        let restored = try await fetchQuota()

        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(raw, for: "zai", at: 0, quietWindow: 300)
        let missingRaw = policy.recordSuccess(percentageOnly, for: "zai", at: 10, quietWindow: 300)
        let returnedRaw = policy.recordSuccess(restored, for: "zai", at: 20, quietWindow: 300)

        XCTAssertEqual(missingRaw.classification, .unchanged)
        XCTAssertEqual(returnedRaw.classification, .unchanged)
    }

    private func fetchQuota() async throws -> ProviderQuota {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = ZAIProvider(
            session: URLSession(configuration: configuration),
            errorLog: ZAIProviderTests.makeErrorLog()
        )
        return try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: ZAIProvider.baseURL)
    }

    private func serve(quotaData: Data, subscriptionJSON: Data) {
        MockURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/quota/limit") == true
                ? (200, quotaData)
                : (200, subscriptionJSON)
        }
    }

    private static func subscriptionJSON(version: String) -> Data {
        Data("""
        {"data": [{"status": "VALID", "version": "\(version)"}], "success": true}
        """.utf8)
    }

    private static func creditQuotaJSON(
        allowance: Double,
        currentValue: Double,
        percentage: Double
    ) -> Data {
        Data("""
        {
          "data": {
            "limits": [
              {"type": "CREDIT_LIMIT", "unit": 3, "number": 5,
               "usage": \(allowance), "currentValue": \(currentValue),
               "remaining": \(allowance - currentValue), "percentage": \(percentage)}
            ]
          }
        }
        """.utf8)
    }

    private static func percentageOnlyQuotaJSON(percentage: Double) -> Data {
        Data("""
        {
          "data": {
            "limits": [
              {"type": "CREDIT_LIMIT", "unit": 3, "number": 5,
               "usage": 100000, "remaining": 99000, "percentage": \(percentage)}
            ]
          }
        }
        """.utf8)
    }
}
