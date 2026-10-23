import Core
import XCTest
@testable import ZAIProvider

final class ZAIForecastMappingTests: XCTestCase {
    private let week: TimeInterval = 7 * 24 * 60 * 60
    private let fiveHour = ZAIProvider.fiveHourLineId
    private let weekly = ZAIProvider.weeklyLineId
    private let webTool = ZAIProvider.monthlyWebToolLineId
    /// The user's weekly reset in the 2026-08-18 capture fell on a Sunday.
    private let weeklyReset = date("2026-10-18T02:02:45.998Z")

    func testTheFiveHourAndWebToolWindowsCarryNoDescriptor() throws {
        let quota = try map(fixture: "quota-legacy-v2", at: date("2026-08-18T20:00:00.000Z"))

        for id in [fiveHour, webTool, "\(webTool)-absolute"] {
            let metric = try XCTUnwrap(metric(id, in: quota), id)
            XCTAssertNil(metric.forecastDescriptor, id)
        }
    }

    func testATokensWindowCarriesAPercentageDescriptor() throws {
        let receivedAt = date("2026-08-18T20:00:00.000Z")

        let quota = try map(fixture: "quota-legacy-v2", at: receivedAt)

        XCTAssertEqual(metric(weekly, in: quota)?.forecastDescriptor, AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: 100, resetsAt: date("2026-08-23T02:02:45.998Z"), length: week),
            unit: .percentagePoints,
            resolution: 1,
            timing: .receipt(receivedAt),
            usageLineId: weekly
        ))
        XCTAssertEqual(quota.activityObservation?.freshness, .fresh)
        XCTAssertEqual(quota.lastUpdated, receivedAt)
    }

    func testACreditWindowCarriesACreditsDescriptorOnItsAbsoluteMetric() throws {
        let receivedAt = date("2026-08-06T20:00:00.000Z")

        let quota = try map(fixture: "quota-credits", at: receivedAt)

        XCTAssertNil(metric(weekly, in: quota)?.forecastDescriptor)
        XCTAssertEqual(metric("\(weekly)-absolute", in: quota)?.forecastDescriptor, AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: 10000, resetsAt: date("2026-08-13T22:34:46.998Z"), length: week),
            unit: .credits,
            resolution: 1,
            timing: .receipt(receivedAt),
            usageLineId: weekly
        ))
        XCTAssertNil(metric("\(fiveHour)-absolute", in: quota)?.forecastDescriptor)
    }

    func testACreditWindowWithoutUsedCreditsOrAnAllowanceCarriesNoDescriptor() throws {
        let windows = [
            Limit.credits(used: nil, allowance: 10000, percentage: 1, resetsAt: weeklyReset),
            Limit.credits(used: 0, allowance: 0, percentage: 0, resetsAt: weeklyReset),
            Limit.credits(used: 71, allowance: nil, percentage: 1, resetsAt: weeklyReset),
        ]
        for window in windows {
            let quota = try map(limits: [window], at: date("2026-10-13T12:00:00.000Z"))

            XCTAssertTrue(quota.activityObservation?.metrics.allSatisfy { $0.forecastDescriptor == nil } ?? false)
        }
    }

    func testAWeeklyWindowWithoutAResetCarriesNoDescriptor() throws {
        let quota = try map(
            limits: [.tokens(percentage: 16, resetsAt: nil)],
            at: date("2026-10-13T12:00:00.000Z")
        )

        XCTAssertNil(metric(weekly, in: quota)?.forecastDescriptor)
    }

    func testARepeatedWeeklyWindowCarriesNoDescriptor() throws {
        let quota = try map(
            limits: [
                .tokens(percentage: 16, resetsAt: weeklyReset),
                .credits(used: 71, allowance: 10000, percentage: 1, resetsAt: weeklyReset),
            ],
            at: date("2026-10-13T12:00:00.000Z")
        )

        XCTAssertTrue(quota.activityObservation?.metrics.allSatisfy { $0.forecastDescriptor == nil } ?? false)
    }

    func testLinesHaveIDsALimitGroupAndTheHeadlineLine() throws {
        let quota = try map(fixture: "quota-legacy-v2", at: date("2026-08-18T20:00:00.000Z"))

        XCTAssertEqual(quota.lines.map(\.id), [fiveHour, weekly, webTool])
        XCTAssertEqual(quota.lines.map(\.limitGroup), [
            ZAIProvider.codingPlanLimitGroup,
            ZAIProvider.codingPlanLimitGroup,
            nil,
        ])
        XCTAssertEqual(quota.headlineUsageLineId, fiveHour)
    }

    func testTheWeeklyLineIsTheHeadlineLineWithoutAFiveHourWindow() throws {
        let weeklyOnly = try map(limits: [.tokens(percentage: 16, resetsAt: weeklyReset)], at: weeklyReset)
        let neither = try map(limits: [.webTool(used: 3, allowance: 1000)], at: weeklyReset)

        XCTAssertEqual(weeklyOnly.headlineUsageLineId, weekly)
        XCTAssertNil(neither.headlineUsageLineId)
    }

    func testResetJitterKeepsOnePeriodAndIsNoChange() throws {
        let first = try map(
            limits: [.credits(used: 71, allowance: 10000, percentage: 1, resetsAt: date("2026-10-18T02:02:45.998Z"))],
            at: date("2026-10-13T12:00:00.000Z")
        )
        let second = try map(
            limits: [.credits(used: 71, allowance: 10000, percentage: 1, resetsAt: date("2026-10-18T02:02:45.999Z"))],
            at: date("2026-10-13T12:01:00.000Z")
        )

        let firstPeriod = try XCTUnwrap(period(in: first))
        let secondPeriod = try XCTUnwrap(period(in: second))
        XCTAssertEqual(firstPeriod.length, secondPeriod.length)
        XCTAssertTrue(AllowanceForecastDescriptor.isSamePeriod(
            resetsAt: secondPeriod.resetsAt,
            periodResetsAt: firstPeriod.resetsAt
        ))
        var policy = SmartRefreshPolicy()
        policy.recordSuccess(first, for: ZAIProvider.providerId, at: 0, quietWindow: 300)
        let decision = policy.recordSuccess(second, for: ZAIProvider.providerId, at: 60, quietWindow: 300)
        XCTAssertEqual(decision.classification, .unchanged)
    }

    func testAReadWithoutUsedCreditsIsNoChange() throws {
        let withCredits = Limit.credits(used: 71, allowance: 10000, percentage: 1, resetsAt: weeklyReset)
        let withoutCredits = Limit.credits(used: nil, allowance: 10000, percentage: 1, resetsAt: weeklyReset)
        let first = try map(limits: [withCredits], at: date("2026-10-13T12:00:00.000Z"))
        let second = try map(limits: [withoutCredits], at: date("2026-10-13T12:01:00.000Z"))
        let third = try map(limits: [withCredits], at: date("2026-10-13T12:02:00.000Z"))
        var policy = SmartRefreshPolicy()

        policy.recordSuccess(first, for: ZAIProvider.providerId, at: 0, quietWindow: 300)
        let missing = policy.recordSuccess(second, for: ZAIProvider.providerId, at: 60, quietWindow: 300)
        let restored = policy.recordSuccess(third, for: ZAIProvider.providerId, at: 120, quietWindow: 300)

        XCTAssertEqual(missing.classification, .unchanged)
        XCTAssertEqual(restored.classification, .unchanged)
    }

    func testTheWeeklyWindowRollsOverOnTheSubscriptionAnchor() throws {
        let weekStart = weeklyReset.addingTimeInterval(-week)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        XCTAssertEqual(calendar.component(.weekday, from: weekStart), 1)
        let nextReset = weeklyReset.addingTimeInterval(week)
        var forecaster = AllowanceForecaster()
        var states: [AllowanceForecast.State?] = []
        for halfHour in 1 ... 338 {
            let receivedAt = weekStart.addingTimeInterval(TimeInterval(halfHour) * 30 * 60)
            let window = receivedAt < weeklyReset
                ? Limit.credits(used: halfHour * 10, allowance: 10000, percentage: halfHour / 10, resetsAt: weeklyReset)
                : Limit.credits(used: 0, allowance: 10000, percentage: 0, resetsAt: nextReset)
            let quota = try map(limits: [window], at: receivedAt)
            states.append(state(after: quota, in: &forecaster))
        }

        XCTAssertEqual(states[334], .beyondReset(resetsAt: weeklyReset))
        XCTAssertEqual(states[336], .insufficient)
        XCTAssertEqual(states[337], .insufficient)
    }

    func testAResetCardStartsANewPeriodFromItsUse() throws {
        let cardUsedAt = weeklyReset.addingTimeInterval(-4 * 24 * 60 * 60)
        var forecaster = AllowanceForecaster()

        let before = try map(
            limits: [.credits(used: 9000, allowance: 10000, percentage: 90, resetsAt: weeklyReset)],
            at: cardUsedAt.addingTimeInterval(-60)
        )
        let after = try map(
            limits: [.credits(used: 0, allowance: 10000, percentage: 0, resetsAt: cardUsedAt.addingTimeInterval(week))],
            at: cardUsedAt.addingTimeInterval(60)
        )
        _ = state(after: before, in: &forecaster)

        let period = try XCTUnwrap(period(in: after))
        XCTAssertEqual(period.resetsAt.addingTimeInterval(-period.length), cardUsedAt)
        XCTAssertEqual(state(after: after, in: &forecaster), .insufficient)
    }

    func testADropWithoutAResetKeepsAveragingFromThePeriodStart() throws {
        let weekStart = weeklyReset.addingTimeInterval(-week)
        let dropAt = weekStart.addingTimeInterval(4 * 24 * 60 * 60)
        var forecaster = AllowanceForecaster()
        var states: [AllowanceForecast.State?] = []
        for halfHour in 1 ... 196 {
            let receivedAt = weekStart.addingTimeInterval(TimeInterval(halfHour) * 30 * 60)
            let used = receivedAt < dropAt ? halfHour * 45 : (halfHour - 192) * 45
            let window = Limit.credits(used: used, allowance: 10000, percentage: used / 100, resetsAt: weeklyReset)
            let quota = try map(limits: [window], at: receivedAt)
            states.append(state(after: quota, in: &forecaster))
        }

        guard case .estimated? = states[190] else {
            return XCTFail("Expected an estimate before the drop, got \(String(describing: states[190]))")
        }
        XCTAssertEqual(states[191], .beyondReset(resetsAt: weeklyReset))
        XCTAssertEqual(states[195], .beyondReset(resetsAt: weeklyReset))
    }

    func testAWeeklyWindowAtItsLimitIsExhausted() throws {
        let windows = [
            Limit.credits(used: 10000, allowance: 10000, percentage: 100, resetsAt: weeklyReset),
            Limit.tokens(percentage: 100, resetsAt: weeklyReset),
        ]
        for window in windows {
            var forecaster = AllowanceForecaster()

            let quota = try map(limits: [window], at: date("2026-10-13T12:00:00.000Z"))

            XCTAssertEqual(state(after: quota, in: &forecaster), .exhausted)
        }
    }

    private func map(limits: [Limit], at receivedAt: Date) throws -> ProviderQuota {
        let json = #"{"data": {"limits": [\#(limits.map(\.json).joined(separator: ", "))]}}"#
        return try map(data: Data(json.utf8), at: receivedAt)
    }

    private func map(fixture name: String, at receivedAt: Date) throws -> ProviderQuota {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try map(data: Data(contentsOf: url), at: receivedAt)
    }

    private func map(data: Data, at receivedAt: Date) throws -> ProviderQuota {
        let envelope = try JSONDecoder().decode(ZAIQuotaEnvelope.self, from: data)
        return try ZAIProvider().map(XCTUnwrap(envelope.data), subscriptionVersion: nil, receivedAt: receivedAt)
    }

    private func metric(_ id: String, in quota: ProviderQuota) -> ProviderActivityMetric? {
        quota.activityObservation?.metrics.first { $0.id == id }
    }

    private func period(in quota: ProviderQuota) -> (resetsAt: Date, length: TimeInterval)? {
        let descriptor = quota.activityObservation?.metrics.compactMap(\.forecastDescriptor).first
        guard case let .fixedPeriod(_, resetsAt, length)? = descriptor?.accounting else { return nil }
        return (resetsAt, length)
    }

    private func state(
        after quota: ProviderQuota,
        in forecaster: inout AllowanceForecaster
    ) -> AllowanceForecast.State? {
        let providerId = ZAIProvider.providerId
        forecaster.record(quota.activityObservation, isStale: false, for: providerId, at: quota.lastUpdated)
        return forecaster.forecasts(for: providerId, at: quota.lastUpdated)[weekly]?.state
    }
}

private func date(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)!
}

private struct Limit {
    let type: String
    let unit: Int
    let number: Int
    let percentage: Int
    var used: Int?
    var allowance: Int?
    var resetsAt: Date?

    static func tokens(percentage: Int, resetsAt: Date?) -> Limit {
        Limit(type: "TOKENS_LIMIT", unit: 6, number: 1, percentage: percentage, resetsAt: resetsAt)
    }

    static func credits(used: Int?, allowance: Int?, percentage: Int, resetsAt: Date?) -> Limit {
        Limit(
            type: "CREDIT_LIMIT",
            unit: 6,
            number: 1,
            percentage: percentage,
            used: used,
            allowance: allowance,
            resetsAt: resetsAt
        )
    }

    static func webTool(used: Int, allowance: Int) -> Limit {
        Limit(type: "TIME_LIMIT", unit: 5, number: 1, percentage: 0, used: used, allowance: allowance)
    }

    var json: String {
        var fields = [
            #""type": "\#(type)""#,
            #""unit": \#(unit)"#,
            #""number": \#(number)"#,
            #""percentage": \#(percentage)"#,
        ]
        if let used {
            fields.append(#""currentValue": \#(used)"#)
        }
        if let allowance {
            fields.append(#""usage": \#(allowance)"#)
        }
        if let resetsAt {
            fields.append(#""nextResetTime": \#(Int64((resetsAt.timeIntervalSince1970 * 1000).rounded()))"#)
        }
        return "{\(fields.joined(separator: ", "))}"
    }
}
