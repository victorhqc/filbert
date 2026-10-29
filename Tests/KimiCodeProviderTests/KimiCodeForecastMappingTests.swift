import Core
@testable import KimiCodeProvider
import XCTest

final class KimiCodeForecastMappingTests: KimiCodeProviderTestCase {
    func testTheFiveHourWindowCarriesAFixedPeriodDescriptor() async throws {
        let quota = try await fetch(json: """
        {"usages":{
          "limit_5h":{"used_ratio":0.4372,"reset_time":"2099-01-01T05:00:00Z"},
          "limit_7d":{"used_ratio":0.2,"reset_time":"2099-01-07T00:00:00Z"},
          "limit_month_total":{"used_ratio":0.3,"reset_time":"2099-02-01T00:00:00Z"}
        }}
        """)

        let expected = try AllowanceForecastDescriptor(
            accounting: .fixedPeriod(
                limit: 100,
                resetsAt: date("2099-01-01T05:00:00Z"),
                length: UsageWindowDuration.fiveHours
            ),
            unit: .percentagePoints,
            resolution: XCTUnwrap(Decimal(string: "0.01")),
            timing: .receipt(quota.lastUpdated),
            usageLineId: "five-hour-usage"
        )
        XCTAssertEqual(descriptors(in: quota), [expected, nil, nil])
    }

    func testAnUnusedFiveHourWindowWithAResetCarriesADescriptor() async throws {
        let quota = try await fetch(json: """
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2099-01-01T05:00:00Z"}}}
        """)

        let metric = try XCTUnwrap(quota.activityObservation?.metrics.first)
        XCTAssertEqual(metric.value, .number(0))
        XCTAssertNotNil(metric.forecastDescriptor)
    }

    func testAFiveHourWindowWithoutAResetCarriesNoDescriptor() async throws {
        let quota = try await fetch(json: #"{"usages":{"limit_5h":{"used_ratio":0.1}}}"#)

        XCTAssertEqual(descriptors(in: quota), [nil])
    }

    func testTheLiveNewPlanForecastsOnlyTheFiveHourWindow() async throws {
        let quota = try await fetch(fixture("usages-live-new-plan"))

        let resets = descriptors(in: quota).map { descriptor -> Date? in
            guard case let .fixedPeriod(_, resetsAt, _)? = descriptor?.accounting else { return nil }
            return resetsAt
        }
        XCTAssertEqual(resets, try [date("2026-10-27T11:15:50Z"), nil])
    }

    func testAnExhaustedLegacyCounterKeepsItsResetInTheDescriptor() async throws {
        let quota = try await fetch(fixture("usages-api-key-contradiction"))

        let metric = try XCTUnwrap(quota.activityObservation?.metrics.first)
        XCTAssertEqual(metric.value, .number(100))
        guard case let .fixedPeriod(_, resetsAt, _)? = metric.forecastDescriptor?.accounting else {
            return XCTFail("Expected a fixed-period descriptor")
        }
        XCTAssertEqual(resetsAt, try date("2026-10-06T13:23:46.915474Z"))
    }

    private func descriptors(in quota: ProviderQuota) -> [AllowanceForecastDescriptor?] {
        quota.activityObservation?.metrics.map(\.forecastDescriptor) ?? []
    }
}
