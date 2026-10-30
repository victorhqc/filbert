import Core
@testable import OpenCodeGoProvider
import XCTest

final class OpenCodeGoForecastMappingTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let rolling = OpenCodeGoProvider.rollingWindowLineId
    private let weekly = OpenCodeGoProvider.weeklyWindowLineId
    private let monthly = OpenCodeGoProvider.monthlyWindowLineId

    func testTheRollingWindowCarriesNoDescriptor() throws {
        let quota = try map(at: date("2026-10-13T09:30:00.000Z"))

        let metric = try XCTUnwrap(metric(rolling, in: quota))
        XCTAssertEqual(metric.value, .number(3))
        XCTAssertNil(metric.forecastDescriptor)
    }

    func testWeeklyAndMonthlyCarryFixedPeriodDescriptors() throws {
        let receivedAt = date("2026-10-13T09:30:00.000Z")
        let weeklyReset = date("2026-10-19T00:00:00.734Z")
        let monthlyReset = date("2026-10-21T08:15:00.734Z")

        let quota = try map(
            weekly: Window(percent: 40, resetsAt: weeklyReset),
            monthly: Window(percent: 31, resetsAt: monthlyReset),
            at: receivedAt
        )

        XCTAssertEqual(metric(weekly, in: quota)?.forecastDescriptor, AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: 100, resetsAt: weeklyReset, length: 7 * day),
            unit: .percentagePoints,
            resolution: 1,
            timing: .receipt(receivedAt),
            usageLineId: weekly
        ))
        XCTAssertEqual(metric(monthly, in: quota)?.forecastDescriptor, AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: 100, resetsAt: monthlyReset, length: 30 * day),
            unit: .percentagePoints,
            resolution: 1,
            timing: .receipt(receivedAt),
            usageLineId: monthly
        ))
        XCTAssertEqual(quota.lines.map(\.windowDuration), [UsageWindowDuration.fiveHours, 7 * day, 30 * day])
        XCTAssertEqual(quota.activityObservation?.freshness, .fresh)
        XCTAssertEqual(quota.lastUpdated, receivedAt)
    }

    func testLinesMatchTheirMetricsShareOneLimitGroupAndNoneIsTheHeadline() throws {
        let quota = try map(at: date("2026-10-13T09:30:00.000Z"))

        XCTAssertEqual(quota.lines.map(\.id), [rolling, weekly, monthly])
        XCTAssertEqual(quota.activityObservation?.metrics.map(\.id), [rolling, weekly, monthly])
        XCTAssertEqual(Set(quota.lines.map(\.limitGroup)), [OpenCodeGoProvider.subscriptionLimitGroup])
        XCTAssertNil(quota.headlineUsageLineId)
    }

    func testResetJitterKeepsOnePeriodAndIsNoChange() throws {
        let first = try map(
            weekly: Window(percent: 40, resetsAt: date("2026-10-19T00:00:00.123Z")),
            monthly: Window(percent: 31, resetsAt: date("2026-10-21T08:15:00.123Z")),
            at: date("2026-10-13T09:30:00.123Z")
        )
        let second = try map(
            weekly: Window(percent: 40, resetsAt: date("2026-10-19T00:00:00.987Z")),
            monthly: Window(percent: 31, resetsAt: date("2026-10-21T08:15:00.987Z")),
            at: date("2026-10-13T09:30:30.987Z")
        )

        for id in [weekly, monthly] {
            let firstPeriod = try XCTUnwrap(period(id, in: first))
            let secondPeriod = try XCTUnwrap(period(id, in: second))
            XCTAssertEqual(firstPeriod.length, secondPeriod.length, id)
            XCTAssertTrue(AllowanceForecastDescriptor.isSamePeriod(
                resetsAt: secondPeriod.resetsAt,
                periodResetsAt: firstPeriod.resetsAt
            ), id)
        }
        var policy = SmartRefreshPolicy()
        policy.recordSuccess(first, for: OpenCodeGoProvider.providerId, at: 0, quietWindow: 300)
        let decision = policy.recordSuccess(second, for: OpenCodeGoProvider.providerId, at: 30, quietWindow: 300)
        XCTAssertEqual(decision.classification, .unchanged)
    }

    func testTheWeeklyWindowRollsOverOnMondayIntoANewPeriod() throws {
        let weekStart = date("2026-10-12T00:00:00.000Z")
        let weekEnd = weekStart.addingTimeInterval(7 * day)
        let monthly = Window(percent: 20, resetsAt: date("2026-10-21T08:15:00.000Z"))
        var forecaster = AllowanceForecaster()
        var states: [AllowanceForecast.State?] = []
        for halfHour in 1 ... 338 {
            let receivedAt = weekStart.addingTimeInterval(TimeInterval(halfHour) * 30 * 60)
            let weekly = receivedAt < weekEnd
                ? Window(percent: halfHour / 6, resetsAt: weekEnd)
                : Window(percent: 0, resetsAt: weekEnd.addingTimeInterval(7 * day))
            let quota = try map(weekly: weekly, monthly: monthly, at: receivedAt)
            states.append(state(of: self.weekly, after: quota, in: &forecaster))
        }

        XCTAssertEqual(states[333], .beyondReset(resetsAt: weekEnd))
        XCTAssertEqual(states[336], .insufficient)
        XCTAssertEqual(states[337], .insufficient)
    }

    func testTheMonthlyWindowRollsOverOnTheSubscriptionAnchor() throws {
        let reset = date("2026-10-21T08:15:00.000Z")
        let nextReset = date("2026-11-21T08:15:00.000Z")
        var forecaster = AllowanceForecaster()

        let before = try map(monthly: Window(percent: 60, resetsAt: reset), at: reset.addingTimeInterval(-600))
        let after = try map(monthly: Window(percent: 0, resetsAt: nextReset), at: reset.addingTimeInterval(600))
        _ = state(of: monthly, after: before, in: &forecaster)

        XCTAssertEqual(period(monthly, in: before)?.length, 30 * day)
        XCTAssertEqual(period(monthly, in: after)?.length, 31 * day)
        XCTAssertEqual(state(of: monthly, after: after, in: &forecaster), .insufficient)
    }

    func testAWindowPinnedAt100IsExhausted() throws {
        let quota = try map(
            weekly: Window(percent: 100, resetsAt: date("2026-10-19T00:00:00.000Z"), status: "rate-limited"),
            at: date("2026-10-13T09:30:00.000Z")
        )
        var forecaster = AllowanceForecaster()

        XCTAssertEqual(state(of: weekly, after: quota, in: &forecaster), .exhausted)
    }

    private struct Window {
        let percent: Int
        let resetsAt: Date
        var status = "ok"

        var json: String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let reset = formatter.string(from: resetsAt)
            return #"{"status": "\#(status)", "percent": \#(percent), "resetsAt": "\#(reset)"}"#
        }
    }

    private func map(
        weekly: Window? = nil,
        monthly: Window? = nil,
        at receivedAt: Date
    ) throws -> ProviderQuota {
        let rolling = Window(percent: 3, resetsAt: receivedAt.addingTimeInterval(4 * 60 * 60))
        let weekly = weekly ?? Window(percent: 10, resetsAt: date("2026-10-19T00:00:00.000Z"))
        let monthly = monthly ?? Window(percent: 20, resetsAt: date("2026-10-21T08:15:00.000Z"))
        let json = #"{"usage": {"rolling": \#(rolling.json), "weekly": \#(weekly.json), "monthly": \#(monthly.json)}}"#
        let response = try OpenCodeGoProvider.decoder.decode(OpenCodeGoUsageResponse.self, from: Data(json.utf8))
        return OpenCodeGoProvider().map(response, receivedAt: receivedAt)
    }

    private func metric(_ id: String, in quota: ProviderQuota) -> ProviderActivityMetric? {
        quota.activityObservation?.metrics.first { $0.id == id }
    }

    private func period(_ id: String, in quota: ProviderQuota) -> (resetsAt: Date, length: TimeInterval)? {
        guard case let .fixedPeriod(_, resetsAt, length)? = metric(id, in: quota)?.forecastDescriptor?.accounting else {
            return nil
        }
        return (resetsAt, length)
    }

    private func state(
        of lineId: String,
        after quota: ProviderQuota,
        in forecaster: inout AllowanceForecaster
    ) -> AllowanceForecast.State? {
        let providerId = OpenCodeGoProvider.providerId
        forecaster.record(quota.activityObservation, isStale: false, for: providerId, at: quota.lastUpdated)
        return forecaster.forecasts(for: providerId, at: quota.lastUpdated)[lineId]?.state
    }

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)!
    }
}
