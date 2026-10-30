import Core
import Foundation
@testable import KimiCodeProvider
import XCTest

final class KimiCodeCaptureReplayTests: XCTestCase {
    private struct Read: Decodable {
        let receivedAt: TimeInterval
        let body: KimiCodeUsagesResponse
    }

    private let firstUse = "kimi-capture-five-hour-first-use"
    private let steadyUse = "kimi-capture-five-hour-steady-use"
    private let rollover = "kimi-capture-five-hour-rollover"
    private let blockResetsAt: TimeInterval = 1_793_315_750
    private let fiveHourLineId = KimiCodeProvider.fiveHourLineId

    func testAnUnusedBlockAlreadyRunsBeforeTheFirstRequest() throws {
        let quotas = try replay(firstUse)
        let unused = try XCTUnwrap(metric(in: quotas[0]))
        guard case let .fixedPeriod(_, resetsAt, length)? = unused.forecastDescriptor?.accounting else {
            return XCTFail("Expected a fixed-period descriptor at 0%")
        }

        XCTAssertEqual(unused.value, .number(0))
        XCTAssertLessThan(resetsAt.addingTimeInterval(-length), quotas[0].lastUpdated)
        XCTAssertNotEqual(metric(in: quotas[1])?.value, .number(0))
    }

    func testUseInsideABlockKeepsOnePeriodAndNeverDecreases() throws {
        XCTAssertEqual(try periodFirstResets(in: replay(firstUse)), [blockResetsAt])
        XCTAssertEqual(try periodFirstResets(in: replay(steadyUse)), [blockResetsAt])
    }

    func testTheRolloverStartsTheNextBlockFiveHoursLater() throws {
        let periods = try periodFirstResets(in: replay(rollover))

        XCTAssertEqual(periods, [blockResetsAt, blockResetsAt + UsageWindowDuration.fiveHours])
    }

    func testSmartRefreshSeesAChangeOnlyAtTheReset() throws {
        let quotas = try replay(rollover)
        let start = try XCTUnwrap(quotas.first?.lastUpdated)
        let resetIndex = try XCTUnwrap(quotas.firstIndex { metric(in: $0)?.value == .number(0) })
        let resetsBeforeTheDrop = Set(quotas[..<resetIndex].compactMap(resetsAt))
        var policy = SmartRefreshPolicy()

        let changed = quotas.indices.filter { index in
            policy.recordSuccess(
                quotas[index],
                for: KimiCodeProvider.providerId,
                at: quotas[index].lastUpdated.timeIntervalSince(start),
                quietWindow: 300
            ).classification == .changed
        }

        XCTAssertGreaterThan(resetsBeforeTheDrop.count, 1)
        XCTAssertEqual(changed, [resetIndex])
    }

    func testSteadyUseReachesARecentPaceEstimateBeforeTheReset() throws {
        let forecasts = try forecasts(in: replay(steadyUse))

        let estimated = try XCTUnwrap(forecasts.firstIndex { $0?.state.isEstimated == true })
        XCTAssertEqual(forecasts.first??.state, .insufficient)
        XCTAssertTrue(forecasts[1 ..< estimated].allSatisfy { $0?.state == .learning })
        let last = try XCTUnwrap(forecasts.last ?? nil)
        guard case let .estimated(depletesAt) = last.state else {
            return XCTFail("Expected an estimate, got \(last.state)")
        }
        XCTAssertLessThan(depletesAt, Date(timeIntervalSince1970: blockResetsAt))
        XCTAssertEqual(last.pace, .recent)
    }

    private func replay(_ fixture: String) throws -> [ProviderQuota] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json"))
        let reads = try JSONDecoder().decode([Read].self, from: Data(contentsOf: url))
        let provider = KimiCodeProvider()
        return reads.map { provider.map($0.body, receivedAt: Date(timeIntervalSince1970: $0.receivedAt)) }
    }

    private func metric(in quota: ProviderQuota) -> ProviderActivityMetric? {
        quota.activityObservation?.metrics.first { $0.id == fiveHourLineId }
    }

    private func resetsAt(in quota: ProviderQuota) -> Date? {
        guard case let .fixedPeriod(_, resetsAt, _)? = metric(in: quota)?.forecastDescriptor?.accounting else {
            return nil
        }
        return resetsAt
    }

    private func forecasts(in quotas: [ProviderQuota]) -> [AllowanceForecast?] {
        var forecaster = AllowanceForecaster()
        return quotas.map { quota in
            if let observation = quota.activityObservation {
                forecaster.record(observation, isStale: false, for: KimiCodeProvider.providerId, at: quota.lastUpdated)
            }
            return forecaster.forecasts(for: KimiCodeProvider.providerId, at: quota.lastUpdated)[fiveHourLineId]
        }
    }

    /// Fails on any decrease inside a period, which Core would read as a correction.
    private func periodFirstResets(in quotas: [ProviderQuota]) -> [TimeInterval] {
        var firstReset: Date?
        var latestValue: Decimal?
        var periods: [TimeInterval] = []
        for quota in quotas {
            guard case let .number(value)? = metric(in: quota)?.value, let resetsAt = resetsAt(in: quota) else {
                XCTFail("Expected a five-hour descriptor at \(quota.lastUpdated)")
                continue
            }
            let continuesPeriod = firstReset.map {
                AllowanceForecastDescriptor.isSamePeriod(resetsAt: resetsAt, periodResetsAt: $0)
            } ?? false
            if continuesPeriod, let latestValue {
                XCTAssertGreaterThanOrEqual(value, latestValue, "at \(quota.lastUpdated)")
            } else {
                firstReset = resetsAt
                periods.append(resetsAt.timeIntervalSince1970)
            }
            latestValue = value
        }
        return periods
    }
}

private extension AllowanceForecast.State {
    var isEstimated: Bool {
        if case .estimated = self {
            return true
        }
        return false
    }
}
