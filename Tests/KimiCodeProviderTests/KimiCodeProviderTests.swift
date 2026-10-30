import Core
@testable import KimiCodeProvider
import XCTest

final class KimiCodeProviderTests: KimiCodeProviderTestCase {
    // MARK: - Request

    func testFetchQuota_issuesAuthenticatedUsagesRequest() async throws {
        _ = try await fetch(fixture("usages-monthly-plan"))

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.kimi.ai/coding/v1/usages")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testFetchQuota_followsTheBaseURLOverride() async throws {
        _ = try await fetch(fixture("usages-monthly-plan"), baseURL: KimiCodeProvider.chinaBaseURL)

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://api.kimi.com/coding/v1/usages")
    }

    func testAuthShapeIsAPIKey() {
        guard case .apiKey = KimiCodeProvider.authShape else {
            return XCTFail("Expected an API key provider")
        }
    }

    // MARK: - Live captures

    func testExhaustedLegacyCounterBeatsAZeroRatio() async throws {
        let quota = try await fetch(fixture("usages-api-key-contradiction"))

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "monthly-usage"])
        assertPercentages(quota, [100, 55.31])
        XCTAssertEqual(quota.lines.map(\.resetDate), try [
            date("2026-10-06T13:23:46.915474Z"),
            date("2026-10-22T14:26:29Z"),
        ])
        XCTAssertEqual(quota.headline.resolved, "100.00% · resetting…")
        XCTAssertEqual(quota.headlineUsageLineId, "five-hour-usage")
    }

    func testAgreeingReadingsKeepTheRatioDecimals() async throws {
        let quota = try await fetch(fixture("usages-monthly-plan"))

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "monthly-usage"])
        assertPercentages(quota, [43.72, 78.77])
        XCTAssertEqual(quota.lines.first?.resetDate, try date("2026-09-23T06:47:08Z"))
    }

    func testLiveNewPlanReadsTheRatios() async throws {
        let quota = try await fetch(fixture("usages-live-new-plan"))

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "monthly-usage"])
        assertPercentages(quota, [8.41, 3.3])
        let fiveHourReset = try date("2026-10-27T11:15:50Z")
        XCTAssertEqual(quota.lines.map(\.resetDate), try [fiveHourReset, date("2026-11-27T00:00:00Z")])
        XCTAssertEqual(quota.headline.resolved, "8.41% · \(QuotaFormatting.countdown(to: fiveHourReset))")
    }

    func testExhaustedWeeklyCounterBeatsAZeroRatio() async throws {
        let quota = try await fetch(fixture("usages-weekly-exhausted"))

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "weekly-usage"])
        assertPercentages(quota, [0, 100])
        XCTAssertEqual(quota.lines.last?.resetDate, try date("2026-09-24T02:09:07.465054Z"))
    }

    func testLegacyPlanReadsTheLegacyCounters() async throws {
        let quota = try await fetch(fixture("usages-legacy-plan"))

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "weekly-usage"])
        assertPercentages(quota, [88, 29])
    }

    func testEmptyRatiosReadNoData() async throws {
        let quota = try await fetch(fixture("usages-empty-ratios"))

        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertEqual(quota.headline.resolved, "No data")
        XCTAssertNil(quota.headlineUsageLineId)
        XCTAssertEqual(quota.activityObservation?.metrics.isEmpty, true)
    }

    // MARK: - Lines

    func testLinesCarryLabelsWindowsAndOneLimitGroup() async throws {
        let quota = try await fetch(json: """
        {"usages":{
          "limit_month_total":{"used_ratio":0.3},
          "limit_7d":{"used_ratio":0.2},
          "limit_5h":{"used_ratio":0.1}
        }}
        """)

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "weekly-usage", "monthly-usage"])
        XCTAssertEqual(quota.lines.map(\.label.resolved), ["5-hour window", "Weekly", "Monthly"])
        XCTAssertEqual(
            quota.lines.map(\.windowDuration),
            [UsageWindowDuration.fiveHours, UsageWindowDuration.week, UsageWindowDuration.month]
        )
        XCTAssertEqual(quota.lines.map(\.limitGroup), ["membership", "membership", "membership"])
        XCTAssertEqual(quota.lines.map(\.percentageFractionLength), [2, 2, 2])
        XCTAssertTrue(quota.lines.allSatisfy { $0.used == nil && $0.total == nil && $0.balance == nil })
    }

    // MARK: - Headline

    func testHeadlineFallsBackToTheWeeklyWindowWithACountdown() async throws {
        let quota = try await fetch(json: """
        {"usages":{"limit_7d":{"used_ratio":0.2,"reset_time":"2099-01-01T00:00:00Z"},
                   "limit_month_total":{"used_ratio":0.9,"reset_time":"2099-01-01T00:00:00Z"}}}
        """)

        let resetDate = try date("2099-01-01T00:00:00Z")
        XCTAssertEqual(quota.headline.resolved, "20.00% · \(QuotaFormatting.countdown(to: resetDate))")
        XCTAssertEqual(quota.headlineUsageLineId, "weekly-usage")
    }

    func testHeadlineWithoutAResetShowsThePercentageAlone() async throws {
        let quota = try await fetch(json: #"{"usages":{"limit_month_total":{"used_ratio":0.5}}}"#)

        XCTAssertEqual(quota.headline.resolved, "50.00%")
        XCTAssertEqual(quota.headlineUsageLineId, "monthly-usage")
    }

    // MARK: - Activity

    func testEachLineIsAFreshUsageMetric() async throws {
        let quota = try await fetch(fixture("usages-monthly-plan"))

        let observation = try XCTUnwrap(quota.activityObservation)
        XCTAssertEqual(observation.metrics.first?.value, .number(Decimal(0.4372 * 100)))
        XCTAssertEqual(observation.freshness, .fresh)
        XCTAssertEqual(observation.metrics.map(\.id), ["five-hour-usage", "monthly-usage"])
        XCTAssertEqual(observation.metrics.map(\.kind), [.usage, .usage])
        XCTAssertEqual(
            observation.metrics.map(\.value),
            quota.lines.compactMap { $0.percentage.map { .number(Decimal($0)) } }
        )
        XCTAssertEqual(observation.metrics.map { $0.forecastDescriptor != nil }, [true, false])
    }
}
