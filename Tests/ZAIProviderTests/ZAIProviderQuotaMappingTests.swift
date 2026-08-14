import Core
import XCTest
@testable import ZAIProvider

final class ZAIProviderQuotaMappingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testFetchQuota_mapsPercentageAndUsage() async throws {
        let quota = try await fetchQuota(with: standardResponseJSON())
        let fiveHour = quota.lines[0]

        XCTAssertEqual(fiveHour.percentage, 42)
        XCTAssertEqual(fiveHour.used, 420)
    }

    func testFetchQuota_mapsOnlyConsumptionIntoActivityObservation() async throws {
        let quota = try await fetchQuota(with: standardResponseJSON())

        XCTAssertEqual(quota.activityObservation?.availability, nil)
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(420)),
            ProviderActivityMetric(id: "weekly-usage", kind: .usage, value: .number(600)),
            ProviderActivityMetric(id: "monthly-web-tool-usage", kind: .usage, value: .number(15)),
        ])
    }

    func testFetchQuota_includesExistingPeakHoursSchedule() async throws {
        let quota = try await fetchQuota(with: standardResponseJSON())
        let config = try XCTUnwrap(quota.peakHoursConfig)

        XCTAssertEqual(config.timeZone?.identifier, "Asia/Shanghai")
        XCTAssertEqual(config.windows, [PeakHoursWindow(startHour: 14, endHour: 18)])
        XCTAssertEqual(config.peakMultiplier, 3)
        XCTAssertEqual(config.offPeakMultiplier, 2)
        XCTAssertEqual(config.promoMultiplier, 1)
        XCTAssertEqual(config.promoEndDate, ZAIPeakHours.promoEndDate)
        XCTAssertNil(config.effectiveDate)
    }

    func testPeakHoursSchedule_preservesPromotionalCutoff() {
        let config = ZAIProvider.peakHoursConfig
        let promoEndDate = ZAIPeakHours.promoEndDate

        XCTAssertTrue(config.isInPeak(at: utcDate(hour: 6)))
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 6)), 3)
        XCTAssertFalse(config.isInPeak(at: utcDate(hour: 10)))
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 10)), 1)
        XCTAssertEqual(config.multiplier(at: promoEndDate.addingTimeInterval(-1)), 1)
        XCTAssertEqual(config.multiplier(at: promoEndDate), 2)
    }

    func testFetchQuota_currentValueIsUsedAndUsageIsTotal() async throws {
        let quota = try await fetchQuota(with: Data("""
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
        """.utf8))
        let monthly = quota.lines[0]

        XCTAssertEqual(monthly.used, 0)
        XCTAssertEqual(monthly.total, 1000)
    }

    func testFetchQuota_mapsUsageDetails() async throws {
        let quota = try await fetchQuota(with: Data("""
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
        """.utf8))
        let fiveHour = quota.lines[0]

        XCTAssertNotNil(fiveHour.details)
        XCTAssertEqual(fiveHour.details?.count, 1)
        XCTAssertEqual(fiveHour.details?[0].label, "deepseek-v3")
        XCTAssertEqual(fiveHour.details?[0].value, "200")
    }

    func testFetchQuota_nilDetailsWhenAbsent() async throws {
        let quota = try await fetchQuota(with: Data("""
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 3, "percentage": 50}
            ]
          }
        }
        """.utf8))

        XCTAssertNil(quota.lines[0].details)
    }

    private func fetchQuota(with data: Data) async throws -> ProviderQuota {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = ZAIProvider(session: URLSession(configuration: configuration))
        MockURLProtocol.responseData = data
        MockURLProtocol.responseStatusCode = 200
        return try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: ZAIProvider.baseURL
        )
    }

    private func standardResponseJSON() -> Data {
        Data("""
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 3, "percentage": 42, "usage": 1000, "currentValue": 420},
              {"type": "TOKENS_LIMIT", "unit": 6, "percentage": 60, "usage": 1000, "currentValue": 600},
              {"type": "TIME_LIMIT", "unit": 5, "percentage": 15, "usage": 100, "currentValue": 15}
            ]
          }
        }
        """.utf8)
    }

    private func utcDate(hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 9
        components.day = 1
        components.hour = hour
        return components.date!
    }
}
