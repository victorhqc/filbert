import Core
import Foundation
import XCTest
@testable import ZAIProvider

/// `quota-legacy-v2.json` and `subscription-legacy-v2.json` are sanitized
/// first-party captures (2026-08-18); `quota-credits.json` derives from the
/// real credits-plan payload in CodexBar issue #2724 (2026-08-06).
final class ZAIProviderQuotaMappingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.handler = nil
        MockURLProtocol.capturedRequests = []
        super.tearDown()
    }

    // MARK: - Legacy V2 fixture

    func testFetchQuota_mapsLegacyFixture() async throws {
        serveLegacyFixtures()

        let quota = try await fetchQuota()

        XCTAssertEqual(quota.lines.map(\.label), ["5-hour window", "Weekly", "Monthly web-tool calls"])
        XCTAssertEqual(quota.lines.map(\.percentage), [13, 16, 0])
        XCTAssertEqual(quota.lines.map(\.used), [nil, nil, 0])
        XCTAssertEqual(quota.lines.map(\.total), [nil, nil, 1000])
        XCTAssertEqual(quota.lines[0].windowDuration, UsageWindowDuration.fiveHours)
        XCTAssertEqual(quota.lines[1].windowDuration, UsageWindowDuration.week)
        XCTAssertEqual(quota.lines[0].resetDate?.timeIntervalSince1970 ?? 0, 1_787_093_257.047, accuracy: 0.001)
        let monthlyDetails = try XCTUnwrap(quota.lines[2].details)
        XCTAssertEqual(monthlyDetails.map(\.label), ["search-prime", "web-reader", "zread"])
        XCTAssertTrue(quota.headline.hasPrefix("13%"))
        XCTAssertTrue(quota.headline.contains("·"))
    }

    func testFetchQuota_legacyFixture_attachesLegacyPricing() async throws {
        serveLegacyFixtures()

        let quota = try await fetchQuota()

        let config = try XCTUnwrap(quota.peakHoursConfig)
        XCTAssertEqual(config.timeZone?.identifier, "Asia/Shanghai")
        XCTAssertEqual(config.windows, [PeakHoursWindow(startHour: 14, endHour: 18)])
        XCTAssertEqual(config.peakMultiplier, 3)
        XCTAssertEqual(config.offPeakMultiplier, 1)
        XCTAssertNil(config.promoMultiplier)
        XCTAssertNil(config.promoEndDate)
        XCTAssertNil(config.effectiveDate)
    }

    func testFetchQuota_legacyFixture_activityObservation() async throws {
        serveLegacyFixtures()

        let quota = try await fetchQuota()

        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(13)),
            ProviderActivityMetric(id: "weekly-usage", kind: .usage, value: .number(16)),
            ProviderActivityMetric(id: "monthly-web-tool-usage", kind: .usage, value: .number(0)),
        ])
    }

    // MARK: - Credits fixture

    func testFetchQuota_mapsCreditsFixtureAbsoluteValues() async throws {
        serve(quota: "quota-credits", subscription: "subscription-legacy-v2")

        let quota = try await fetchQuota()

        XCTAssertEqual(quota.lines.map(\.label), ["5-hour window", "Weekly"])
        XCTAssertEqual(quota.lines.map(\.percentage), [3, 1])
        XCTAssertEqual(quota.lines.map(\.used), [71, 71])
        XCTAssertEqual(quota.lines.map(\.total), [2000, 10000])
        XCTAssertEqual(quota.lines[0].resetDate?.timeIntervalSince1970 ?? 0, 1_786_073_946.574, accuracy: 0.001)
        XCTAssertTrue(quota.headline.hasPrefix("3%"))
        XCTAssertTrue(quota.headline.contains("·"))
    }

    func testFetchQuota_creditsFixture_attachesCreditsPricing() async throws {
        serve(quota: "quota-credits", subscription: "subscription-legacy-v2")

        let quota = try await fetchQuota()

        let config = try XCTUnwrap(quota.peakHoursConfig)
        XCTAssertEqual(config.timeZone?.identifier, "Asia/Singapore")
        XCTAssertEqual(config.windows, [PeakHoursWindow(startHour: 14, endHour: 18, weekdays: [2, 3, 4, 5, 6])])
        XCTAssertEqual(config.peakRate, .fractionOfStandardRate(1))
        XCTAssertEqual(config.offPeakRate, .fractionOfStandardRate(0.5))
        XCTAssertNil(config.effectiveDate)
    }

    func testFetchQuota_ignoresUnknownLimitTypes() async throws {
        let quotaJSON = Data("""
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 50},
              {"type": "UNKNOWN_TYPE", "unit": 99, "percentage": 99}
            ]
          }
        }
        """.utf8)
        serve(quotaData: quotaJSON, subscriptionJSON: Self.subscriptionJSON(version: "V2"))

        let quota = try await fetchQuota()

        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].label, "5-hour window")
        XCTAssertEqual(quota.lines[0].windowDuration, UsageWindowDuration.fiveHours)
    }

    // MARK: - Plan selection

    func testFetchQuota_subscriptionFailure_suppressesPricingWithoutFailingRefresh() async throws {
        MockURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/quota/limit") == true
                ? (200, Self.fixture("quota-legacy-v2"))
                : (500, Data())
        }

        let quota = try await fetchQuota()

        XCTAssertNil(quota.peakHoursConfig)
        XCTAssertEqual(quota.lines.count, 3)
    }

    func testFetchQuota_unknownSubscriptionVersion_suppressesPricing() async throws {
        serve(
            quotaData: Self.fixture("quota-legacy-v2"),
            subscriptionJSON: Self.subscriptionJSON(version: "V3")
        )

        let quota = try await fetchQuota()

        XCTAssertNil(quota.peakHoursConfig)
        XCTAssertEqual(quota.lines.count, 3)
    }

    func testFetchQuota_mixedLimitTypes_suppressesPricing() async throws {
        let quotaJSON = Data("""
        {
          "data" : {
            "limits" : [
              {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 13, "futureField": "x"},
              {"type": "CREDIT_LIMIT", "unit": 6, "number": 1, "usage": 10000, "currentValue": 71,
               "remaining": 9929, "percentage": 1}
            ]
          }
        }
        """.utf8)
        serve(quotaData: quotaJSON, subscriptionJSON: Self.subscriptionJSON(version: "V2"))

        let quota = try await fetchQuota()

        XCTAssertNil(quota.peakHoursConfig)
        XCTAssertEqual(quota.lines.map(\.label), ["5-hour window", "Weekly"])
    }

    func testFetchQuota_timeLimitMapsUsedAndTotal() async throws {
        let quotaJSON = Data("""
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
        """.utf8)
        serve(quotaData: quotaJSON, subscriptionJSON: Self.subscriptionJSON(version: "V2"))

        let quota = try await fetchQuota()
        let monthly = quota.lines[0]

        XCTAssertEqual(monthly.used, 0)
        XCTAssertEqual(monthly.total, 1000)
    }

    func testFetchQuota_mapsUsageDetails() async throws {
        let quotaJSON = Data("""
        {
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "percentage": 42,
                "usage": 1000,
                "currentValue": 420,
                "usageDetails": [{"modelCode": "deepseek-v3", "usage": 200}]
              }
            ]
          }
        }
        """.utf8)
        serve(quotaData: quotaJSON, subscriptionJSON: Self.subscriptionJSON(version: "V2"))

        let quota = try await fetchQuota()
        let fiveHour = quota.lines[0]

        XCTAssertEqual(fiveHour.details?.count, 1)
        XCTAssertEqual(fiveHour.details?[0].label, "deepseek-v3")
        XCTAssertEqual(fiveHour.details?[0].value, "200")
    }

    // MARK: - Helpers

    private func fetchQuota() async throws -> ProviderQuota {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = ZAIProvider(session: URLSession(configuration: configuration))
        return try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )
    }

    private static func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    private func serveLegacyFixtures() {
        serve(quota: "quota-legacy-v2", subscription: "subscription-legacy-v2")
    }

    private func serve(quota: String, subscription: String) {
        MockURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/quota/limit") == true
                ? (200, Self.fixture(quota))
                : (200, Self.fixture(subscription))
        }
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
}
