import Core
@testable import CursorProvider
import XCTest

final class CursorForecastMappingTests: EnglishTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let included = CursorProvider.includedUsageLineId
    private let percent = CursorProvider.includedUsagePercentMetricId
    private let cycleStart = date("2026-10-05T14:22:31.000Z")
    private let cycleEnd = date("2026-11-05T14:22:31.000Z")

    func testTheTotalPercentageCarriesAFixedPeriodDescriptor() throws {
        let receivedAt = date("2026-10-13T12:00:00.000Z")

        let quota = try map(Usage(totalPercentUsed: 12.34, cycleStart: cycleStart, cycleEnd: cycleEnd), at: receivedAt)

        XCTAssertEqual(metric(percent, in: quota)?.value, .number(Decimal(12.34)))
        XCTAssertEqual(metric(percent, in: quota)?.forecastDescriptor, AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: 100, resetsAt: cycleEnd, length: 31 * day),
            unit: .percentagePoints,
            resolution: Decimal(1) / 100,
            timing: .receipt(receivedAt),
            usageLineId: included
        ))
        XCTAssertNil(metric(included, in: quota)?.forecastDescriptor)
        XCTAssertEqual(quota.activityObservation?.freshness, .fresh)
        XCTAssertEqual(quota.lastUpdated, receivedAt)
    }

    func testIncludedDollarsAtTheirLimitAreNotExhaustion() throws {
        // maxh213/dandelion tasks/006-cursor.md, an Ultra plan.
        let capture = """
        {"billingCycleStart": "1788108306000", "billingCycleEnd": "1790786706000",
         "planUsage": {"totalSpend": 101050, "includedSpend": 40000, "limit": 40000,
          "autoPercentUsed": 32.36, "apiPercentUsed": 15.81, "totalPercentUsed": 31.09}}
        """
        var forecaster = AllowanceForecaster()

        let quota = try map(data: Data(capture.utf8), at: date("2026-09-15T12:00:00.000Z"))

        let line = try XCTUnwrap(quota.lines.first { $0.id == included })
        XCTAssertEqual(line.used, line.total)
        XCTAssertEqual(line.percentage, 31.09)
        XCTAssertEqual(
            state(after: quota, in: &forecaster),
            .beyondReset(resetsAt: date("2026-09-30T16:45:06.000Z"))
        )
    }

    func testThePeriodLengthComesFromTheBillingCycle() throws {
        let cycles = [
            (date("2027-02-05T14:22:31.000Z"), date("2027-03-05T14:22:31.000Z"), 28 * day),
            (date("2026-11-05T14:22:31.000Z"), date("2026-12-05T14:22:31.000Z"), 30 * day),
            (cycleStart, cycleEnd, 31 * day),
        ]
        for (start, end, length) in cycles {
            let quota = try map(Usage(totalPercentUsed: 12.34, cycleStart: start, cycleEnd: end), at: start)

            let period = try XCTUnwrap(period(in: quota))
            XCTAssertEqual(period.resetsAt, end)
            XCTAssertEqual(period.length, length)
        }
    }

    func testOtherAmountsCarryNoDescriptor() throws {
        var usage = Usage(totalPercentUsed: 12.34, cycleStart: cycleStart, cycleEnd: cycleEnd)
        usage.bonusSpend = 350
        usage.onDemandUsed = 1500
        usage.pooledUsed = 500

        let quota = try map(usage, at: date("2026-10-13T12:00:00.000Z"))

        for id in [included, "bonus-credits", "on-demand-spend", "spend-limit-usage"] {
            let metric = try XCTUnwrap(metric(id, in: quota), id)
            XCTAssertNil(metric.forecastDescriptor, id)
        }
        XCTAssertNotNil(metric(percent, in: quota)?.forecastDescriptor)
    }

    func testTheLegacyShapeCarriesNoDescriptor() throws {
        let quota = try map(data: CursorTestFixtures.legacyResponse(), at: date("2026-10-13T12:00:00.000Z"))

        XCTAssertNotNil(metric(percent, in: quota))
        XCTAssertTrue(quota.activityObservation?.metrics.allSatisfy { $0.forecastDescriptor == nil } ?? false)
    }

    func testAnUnlimitedPlanCarriesNoDescriptor() throws {
        var usage = Usage(totalPercentUsed: 12.34, cycleStart: cycleStart, cycleEnd: cycleEnd)
        usage.isUnlimited = true

        let quota = try map(usage, at: date("2026-10-13T12:00:00.000Z"))

        XCTAssertNil(metric(percent, in: quota)?.forecastDescriptor)
    }

    func testAMissingTotalPercentageCarriesNoDescriptor() throws {
        let usage = Usage(totalPercentUsed: nil, cycleStart: cycleStart, cycleEnd: cycleEnd)

        let quota = try map(usage, at: date("2026-10-13T12:00:00.000Z"))

        XCTAssertNil(metric(percent, in: quota))
        XCTAssertTrue(quota.activityObservation?.metrics.allSatisfy { $0.forecastDescriptor == nil } ?? false)
    }

    func testAMissingOrInvertedCycleCarriesNoDescriptor() throws {
        let cycles: [(start: String?, end: String?)] = [
            (nil, milliseconds(cycleEnd)),
            (milliseconds(cycleStart), nil),
            ("not a date", milliseconds(cycleEnd)),
            (milliseconds(cycleEnd), milliseconds(cycleEnd)),
            (milliseconds(cycleEnd), milliseconds(cycleStart)),
        ]
        for cycle in cycles {
            var usage = Usage(totalPercentUsed: 12.34, cycleStart: cycleStart, cycleEnd: cycleEnd)
            usage.cycleStart = cycle.start
            usage.cycleEnd = cycle.end

            let quota = try map(usage, at: date("2026-10-13T12:00:00.000Z"))

            XCTAssertNotNil(metric(percent, in: quota), "\(cycle)")
            XCTAssertNil(metric(percent, in: quota)?.forecastDescriptor, "\(cycle)")
        }
    }

    func testOnlyTheIncludedLineHasAnIDAndNoLineIsTheHeadlineLine() throws {
        var usage = Usage(totalPercentUsed: 12.34, cycleStart: cycleStart, cycleEnd: cycleEnd)
        usage.bonusSpend = 350
        usage.onDemandUsed = 1500
        usage.pooledUsed = 500

        let quota = try map(usage, at: date("2026-10-13T12:00:00.000Z"))

        XCTAssertEqual(quota.lines.map(\.id), [included, nil, nil, nil])
        XCTAssertEqual(quota.lines.map(\.limitGroup), [nil, nil, nil, nil])
        XCTAssertNil(quota.headlineUsageLineId)
        XCTAssertTrue(quota.headline.resolved.contains("left"), quota.headline.resolved)
    }

    func testRepeatedReadsAreNoChange() throws {
        let usage = Usage(totalPercentUsed: 12.34, cycleStart: cycleStart, cycleEnd: cycleEnd)
        let first = try map(usage, at: date("2026-10-13T12:00:00.000Z"))
        let second = try map(usage, at: date("2026-10-13T12:05:00.000Z"))
        var policy = SmartRefreshPolicy()

        policy.recordSuccess(first, for: CursorProvider.providerId, at: 0, quietWindow: 300)
        let decision = policy.recordSuccess(second, for: CursorProvider.providerId, at: 300, quietWindow: 300)

        XCTAssertEqual(decision.classification, .unchanged)
    }

    func testTheCycleRollsOverIntoANewPeriod() throws {
        let nextEnd = date("2026-12-05T14:22:31.000Z")
        var forecaster = AllowanceForecaster()
        var states: [AllowanceForecast.State?] = [nil]
        for hour in 1 ... 31 * 24 + 25 {
            let receivedAt = cycleStart.addingTimeInterval(TimeInterval(hour) * 60 * 60)
            let usage = receivedAt < cycleEnd
                ? Usage(totalPercentUsed: Double(hour) / 10, cycleStart: cycleStart, cycleEnd: cycleEnd)
                : Usage(totalPercentUsed: Double(hour - 31 * 24) / 10, cycleStart: cycleEnd, cycleEnd: nextEnd)
            try states.append(state(after: map(usage, at: receivedAt), in: &forecaster))
        }

        XCTAssertEqual(states[12], .insufficient)
        XCTAssertEqual(states[31 * 24 - 1], .beyondReset(resetsAt: cycleEnd))
        XCTAssertEqual(states[31 * 24 + 1], .insufficient)
        XCTAssertEqual(states[31 * 24 + 25], .beyondReset(resetsAt: nextEnd))
    }

    func testAnUpgradeRestartsTheCycleAndStartsANewPeriod() throws {
        let upgradedAt = cycleStart.addingTimeInterval(10 * day)
        let upgradedEnd = date("2026-11-15T14:22:31.000Z")
        var forecaster = AllowanceForecaster()

        let before = try map(
            Usage(totalPercentUsed: 50, cycleStart: cycleStart, cycleEnd: cycleEnd),
            at: upgradedAt.addingTimeInterval(-60)
        )
        let after = try map(
            Usage(totalPercentUsed: 0, cycleStart: upgradedAt, cycleEnd: upgradedEnd),
            at: upgradedAt.addingTimeInterval(60)
        )
        _ = state(after: before, in: &forecaster)

        let period = try XCTUnwrap(period(in: after))
        XCTAssertEqual(period.resetsAt.addingTimeInterval(-period.length), upgradedAt)
        XCTAssertEqual(state(after: after, in: &forecaster), .insufficient)
    }

    func testAPercentageDropWithinACycleKeepsAveragingFromTheCycleStart() throws {
        let droppedAt = cycleStart.addingTimeInterval(10 * day)
        var forecaster = AllowanceForecaster()

        let before = try state(
            after: map(Usage(totalPercentUsed: 50, cycleStart: cycleStart, cycleEnd: cycleEnd), at: droppedAt),
            in: &forecaster
        )
        let after = try state(
            after: map(
                Usage(totalPercentUsed: 25, cycleStart: cycleStart, cycleEnd: cycleEnd),
                at: droppedAt.addingTimeInterval(60)
            ),
            in: &forecaster
        )

        guard case let .estimated(depletesAt)? = before else {
            return XCTFail("Expected an estimate before the drop, got \(String(describing: before))")
        }
        XCTAssertEqual(
            depletesAt.timeIntervalSince1970,
            cycleStart.addingTimeInterval(20 * day).timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(after, .beyondReset(resetsAt: cycleEnd))
    }

    func testATotalPercentageAtOrPast100IsExhausted() throws {
        for totalPercentUsed in [100, 100.4] {
            var forecaster = AllowanceForecaster()
            let usage = Usage(totalPercentUsed: totalPercentUsed, cycleStart: cycleStart, cycleEnd: cycleEnd)

            let quota = try map(usage, at: date("2026-10-13T12:00:00.000Z"))

            XCTAssertEqual(state(after: quota, in: &forecaster), .exhausted, "\(totalPercentUsed)")
        }
    }

    private func map(_ usage: Usage, at receivedAt: Date) throws -> ProviderQuota {
        try map(data: CursorTestFixtures.jsonToData(usage.dictionary), at: receivedAt)
    }

    private func map(data: Data, at receivedAt: Date) throws -> ProviderQuota {
        let response = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        return CursorProvider().map(response, receivedAt: receivedAt)
    }

    private func metric(_ id: String, in quota: ProviderQuota) -> ProviderActivityMetric? {
        quota.activityObservation?.metrics.first { $0.id == id }
    }

    private func period(in quota: ProviderQuota) -> (resetsAt: Date, length: TimeInterval)? {
        let descriptor = metric(percent, in: quota)?.forecastDescriptor
        guard case let .fixedPeriod(_, resetsAt, length)? = descriptor?.accounting else { return nil }
        return (resetsAt, length)
    }

    private func state(
        after quota: ProviderQuota,
        in forecaster: inout AllowanceForecaster
    ) -> AllowanceForecast.State? {
        let providerId = CursorProvider.providerId
        forecaster.record(quota.activityObservation, isStale: false, for: providerId, at: quota.lastUpdated)
        return forecaster.forecasts(for: providerId, at: quota.lastUpdated)[included]?.state
    }
}

private func date(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)!
}

private func milliseconds(_ date: Date) -> String {
    String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
}

private struct Usage {
    var totalPercentUsed: Double?
    var includedSpend = 1000
    var limit = 2000
    var cycleStart: String?
    var cycleEnd: String?
    var isUnlimited = false
    var bonusSpend: Int?
    var onDemandUsed: Int?
    var pooledUsed: Int?

    init(totalPercentUsed: Double?, cycleStart: Date, cycleEnd: Date) {
        self.totalPercentUsed = totalPercentUsed
        self.cycleStart = milliseconds(cycleStart)
        self.cycleEnd = milliseconds(cycleEnd)
    }

    var dictionary: [String: Any] {
        var planUsage: [String: Any] = ["includedSpend": includedSpend, "limit": limit]
        if let totalPercentUsed {
            planUsage["totalPercentUsed"] = totalPercentUsed
        }
        if let bonusSpend {
            planUsage["bonusSpend"] = bonusSpend
        }
        var dictionary: [String: Any] = ["isUnlimited": isUnlimited, "planUsage": planUsage]
        if let cycleStart {
            dictionary["billingCycleStart"] = cycleStart
        }
        if let cycleEnd {
            dictionary["billingCycleEnd"] = cycleEnd
        }
        var spendLimitUsage: [String: Any] = [:]
        if let onDemandUsed {
            spendLimitUsage["individualUsed"] = onDemandUsed
            spendLimitUsage["individualLimit"] = 5000
        }
        if let pooledUsed {
            spendLimitUsage["pooledUsed"] = pooledUsed
            spendLimitUsage["pooledLimit"] = 10000
            spendLimitUsage["pooledRemaining"] = 10000 - pooledUsed
        }
        if !spendLimitUsage.isEmpty {
            dictionary["spendLimitUsage"] = spendLimitUsage
        }
        return dictionary
    }
}
