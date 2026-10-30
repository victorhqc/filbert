import Core
@testable import KimiCodeProvider
import XCTest

final class KimiCodeLongPeriodForecastTests: KimiCodeProviderTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    func testTheLegacyWeeklyWindowCarriesASevenDayDescriptor() async throws {
        let quota = try await fetch(fixture("usages-legacy-plan"))

        let weekly = try XCTUnwrap(period(of: KimiCodeProvider.weeklyLineId, in: quota))
        XCTAssertEqual(weekly.resetsAt, try date("2026-10-02T12:58:51.471957Z"))
        XCTAssertEqual(weekly.length, UsageWindowDuration.week)
        XCTAssertNil(period(of: KimiCodeProvider.monthlyLineId, in: quota))
    }

    func testWindowsWithoutAResetCarryNoDescriptorAndNoMonthLength() async throws {
        let quota = try await fetch(json: """
        {"usages":{"limit_7d":{"used_ratio":0.2},"limit_month_total":{"used_ratio":0.3}}}
        """)

        XCTAssertEqual(quota.activityObservation?.metrics.map { $0.forecastDescriptor == nil }, [true, true])
        XCTAssertEqual(quota.lines.map(\.windowDuration), [UsageWindowDuration.week, nil])
    }

    func testTheMonthLengthFollowsTheResetDate() throws {
        let expectedDays: [(reset: String, days: Double)] = [
            ("2026-12-27T00:00:00Z", 30),
            ("2027-02-27T00:00:00Z", 31),
            ("2027-02-28T00:00:00Z", 28),
            ("2028-02-29T00:00:00Z", 29),
            ("2027-03-31T00:00:00Z", 31),
            ("2027-04-30T00:00:00Z", 30),
        ]
        for (reset, days) in expectedDays {
            let quota = try map(monthly(ratio: 0.1, reset: reset), at: date(reset).addingTimeInterval(-2 * day))

            XCTAssertEqual(quota.lines.first?.windowDuration, days * day, reset)
            XCTAssertEqual(period(of: KimiCodeProvider.monthlyLineId, in: quota)?.length, days * day, reset)
        }
    }

    func testAMonthlyRolloverStartsTheNextPeriodAtTheReset() throws {
        let before = try map(monthly(ratio: 0.9, reset: "2026-11-27T00:00:00Z"), at: date("2026-11-26T23:55:00Z"))
        let after = try map(monthly(ratio: 0, reset: "2026-12-27T00:00:00Z"), at: date("2026-11-27T00:05:00Z"))

        let first = try XCTUnwrap(period(of: KimiCodeProvider.monthlyLineId, in: before))
        let next = try XCTUnwrap(period(of: KimiCodeProvider.monthlyLineId, in: after))
        XCTAssertEqual(first.length, 31 * day)
        XCTAssertEqual(next.length, 30 * day)
        XCTAssertEqual(next.resetsAt.addingTimeInterval(-next.length), first.resetsAt)
        XCTAssertFalse(
            AllowanceForecastDescriptor.isSamePeriod(resetsAt: next.resetsAt, periodResetsAt: first.resetsAt)
        )
    }

    func testRepeatedReadsInOnePeriodAreNotAChange() throws {
        let body = monthly(ratio: 0.2, reset: "2026-11-27T00:00:00Z")
        let start = try date("2026-11-06T00:00:00Z")
        let quotas = try [0, 60, 120].map { try map(body, at: start.addingTimeInterval($0)) }
        var policy = SmartRefreshPolicy()

        let changed = quotas.indices.filter { index in
            policy.recordSuccess(
                quotas[index],
                for: KimiCodeProvider.providerId,
                at: quotas[index].lastUpdated.timeIntervalSince(start),
                quietWindow: 300
            ).classification == .changed
        }

        XCTAssertEqual(Set(quotas.map { period(of: KimiCodeProvider.monthlyLineId, in: $0)?.resetsAt }).count, 1)
        XCTAssertEqual(changed, [])
    }

    func testTheMonthlyWindowUsesTheAveragePaceSinceThePeriodStarted() throws {
        let quota = try map(monthly(ratio: 0.5, reset: "2026-11-27T00:00:00Z"), at: date("2026-11-06T00:00:00Z"))

        let forecast = try XCTUnwrap(forecast(of: KimiCodeProvider.monthlyLineId, after: quota))
        guard case let .estimated(depletesAt) = forecast.state else {
            return XCTFail("Expected an estimate, got \(forecast.state)")
        }
        XCTAssertEqual(forecast.pace, .periodAverage)
        XCTAssertEqual(
            depletesAt.timeIntervalSince1970,
            try date("2026-11-16T00:00:00Z").timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testAFullMonthlyPoolIsExhausted() throws {
        let quota = try map(monthly(ratio: 1, reset: "2026-11-27T00:00:00Z"), at: date("2026-11-20T00:00:00Z"))

        XCTAssertEqual(try XCTUnwrap(forecast(of: KimiCodeProvider.monthlyLineId, after: quota)).state, .exhausted)
    }

    private func monthly(ratio: Double, reset: String) -> String {
        #"{"usages":{"limit_month_total":{"used_ratio":\#(ratio),"reset_time":"\#(reset)"}}}"#
    }

    private func map(_ json: String, at receivedAt: Date) throws -> ProviderQuota {
        let response = try JSONDecoder().decode(KimiCodeUsagesResponse.self, from: Data(json.utf8))
        return provider.map(response, receivedAt: receivedAt)
    }

    private func period(of lineId: String, in quota: ProviderQuota) -> (resetsAt: Date, length: TimeInterval)? {
        let metric = quota.activityObservation?.metrics.first { $0.id == lineId }
        guard case let .fixedPeriod(_, resetsAt, length)? = metric?.forecastDescriptor?.accounting else { return nil }
        return (resetsAt, length)
    }

    private func forecast(of lineId: String, after quota: ProviderQuota) -> AllowanceForecast? {
        var forecaster = AllowanceForecaster()
        if let observation = quota.activityObservation {
            forecaster.record(observation, isStale: false, for: KimiCodeProvider.providerId, at: quota.lastUpdated)
        }
        return forecaster.forecasts(for: KimiCodeProvider.providerId, at: quota.lastUpdated)[lineId]
    }
}
