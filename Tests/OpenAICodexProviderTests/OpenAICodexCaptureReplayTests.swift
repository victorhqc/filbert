import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexCaptureReplayTests: XCTestCase {
    private struct Read: Decodable {
        let receivedAt: TimeInterval
        let result: CodexRateLimitReadResult
    }

    private let firstSession = "codex-capture-first-session"
    private let fiveHourRollover = "codex-capture-five-hour-rollover"
    private let creditsSwitch = "codex-capture-credits-switch"

    func testAnUnusedWindowCarriesNoDescriptorUntilItsPercentageRises() throws {
        let metrics = try replay(firstSession).map { metric(OpenAICodexProvider.primaryWindowLineId, in: $0) }

        let firstUsed = try XCTUnwrap(metrics.firstIndex { $0?.value != .number(0) })
        XCTAssertGreaterThan(firstUsed, 0)
        XCTAssertTrue(metrics[..<firstUsed].allSatisfy { $0?.forecastDescriptor == nil })
        XCTAssertTrue(metrics[firstUsed...].allSatisfy { $0?.forecastDescriptor != nil })
    }

    func testTheFirstSessionStaysInOnePeriodPerWindowAndNeverDecreases() throws {
        let periods = try periodFirstResets(in: replay(firstSession))

        XCTAssertEqual(periods[OpenAICodexProvider.primaryWindowLineId], [1_791_828_927])
        XCTAssertEqual(periods[OpenAICodexProvider.secondaryWindowLineId], [1_792_317_872])
    }

    func testSmartRefreshSeesAChangeOnlyWhenUsageRises() throws {
        let quotas = try replay(firstSession)
        let start = try XCTUnwrap(quotas.first?.lastUpdated)
        var policy = SmartRefreshPolicy()

        let changedPercentages = quotas.compactMap { quota -> ProviderActivityMetric.Value? in
            let decision = policy.recordSuccess(
                quota,
                for: OpenAICodexProvider.providerId,
                at: quota.lastUpdated.timeIntervalSince(start),
                quietWindow: 300
            )
            guard decision.classification == .changed else { return nil }
            return metric(OpenAICodexProvider.primaryWindowLineId, in: quota)?.value
        }

        XCTAssertEqual(changedPercentages, [.number(2), .number(4), .number(5), .number(7)])
    }

    func testFlatCreditsKeepOneBalanceDescriptor() throws {
        let balance = try XCTUnwrap(Decimal(string: "811.774902"))
        let metrics = try replay(firstSession).map { metric(OpenAICodexProvider.creditsLineId, in: $0) }

        XCTAssertTrue(metrics.allSatisfy { $0?.value == .number(balance) })
        XCTAssertTrue(metrics.allSatisfy { $0?.forecastDescriptor?.accounting == .balance })
    }

    func testTheFiveHourWindowLearnsOnlyAfterItRisesAndKeepsItsRate() throws {
        let states = try states(of: OpenAICodexProvider.primaryWindowLineId, in: replay(firstSession))

        let baseline = try XCTUnwrap(states.firstIndex { $0 != nil })
        let learning = try XCTUnwrap(states.firstIndex(of: .learning))
        let estimated = try XCTUnwrap(states.firstIndex { $0?.isEstimated == true })
        XCTAssertEqual(states[baseline], .insufficient)
        XCTAssertEqual(learning, baseline + 1)
        XCTAssertTrue(states[learning ..< estimated].allSatisfy { $0 == .learning })
        XCTAssertTrue(states[estimated...].allSatisfy { $0?.isEstimated == true })
    }

    func testFlatCreditsNeverShowLearning() throws {
        let states = try states(of: OpenAICodexProvider.creditsLineId, in: replay(firstSession))

        XCTAssertFalse(states.isEmpty)
        XCTAssertTrue(states.allSatisfy { $0 == .insufficient })
    }

    func testTheFiveHourRolloverStartsANewPeriodAtFirstUse() throws {
        let periods = try periodFirstResets(in: replay(fiveHourRollover))

        XCTAssertEqual(periods[OpenAICodexProvider.primaryWindowLineId], [1_791_828_927, 1_791_847_075])
    }

    func testTheWindowIsUnusedBetweenTheResetAndTheFirstRequest() throws {
        let metrics = try replay(fiveHourRollover).map { metric(OpenAICodexProvider.primaryWindowLineId, in: $0) }

        let unused = metrics.filter { $0?.value == .number(0) }
        XCTAssertEqual(unused.count, 3)
        XCTAssertTrue(unused.allSatisfy { $0?.forecastDescriptor == nil })
    }

    func testTheNewPeriodLearnsOnlyAfterItsFirstRise() throws {
        let quotas = try replay(fiveHourRollover)
        let states = states(of: OpenAICodexProvider.primaryWindowLineId, in: quotas)
        let lastUnused = try XCTUnwrap(quotas.lastIndex {
            metric(OpenAICodexProvider.primaryWindowLineId, in: $0)?.value == .number(0)
        })

        XCTAssertEqual(states[lastUnused], nil)
        XCTAssertEqual(states[lastUnused + 1], .insufficient)
        XCTAssertTrue(states[(lastUnused + 2)...].allSatisfy { $0 == .learning })
    }

    func testCreditsFallFromTheReadThatReachesTheLimitWhileTheWeekStandsStill() throws {
        let quotas = try replay(creditsSwitch)
        let firstDrop = try XCTUnwrap(firstCreditsDrop(in: quotas))
        let fiveHourBefore = try XCTUnwrap(number(OpenAICodexProvider.primaryWindowLineId, in: quotas[firstDrop - 1]))

        XCTAssertLessThan(fiveHourBefore, 100)
        XCTAssertEqual(number(OpenAICodexProvider.primaryWindowLineId, in: quotas[firstDrop]), 100)
        let weekly = Set(quotas[firstDrop...].compactMap { number(OpenAICodexProvider.secondaryWindowLineId, in: $0) })
        XCTAssertEqual(weekly, [66])
    }

    func testTheCreditsForecastCountsOnlyTheSpendingAfterTheSwitch() throws {
        let quotas = try replay(creditsSwitch)
        let states = states(of: OpenAICodexProvider.creditsLineId, in: quotas)
        let firstDrop = try XCTUnwrap(firstCreditsDrop(in: quotas))
        let segmentStart = quotas[firstDrop - 1].lastUpdated
        let lastDrop = try XCTUnwrap(quotas.indices.last { index in
            index > 0 && number(OpenAICodexProvider.creditsLineId, in: quotas[index])
                != number(OpenAICodexProvider.creditsLineId, in: quotas[index - 1])
        })

        XCTAssertTrue(states[..<firstDrop].allSatisfy { $0 == .insufficient })
        for index in firstDrop ... lastDrop where quotas[index].lastUpdated.timeIntervalSince(segmentStart) < 10 * 60 {
            XCTAssertEqual(states[index], .learning, "read \(index)")
        }
        guard case let .estimated(depletesAt)? = states[lastDrop] else {
            return XCTFail("Expected an estimate at the last drop, got \(String(describing: states[lastDrop]))")
        }
        XCTAssertEqual(depletesAt.timeIntervalSince(quotas[lastDrop].lastUpdated), 198.6 * 60, accuracy: 60)
    }

    private func firstCreditsDrop(in quotas: [ProviderQuota]) -> Int? {
        quotas.indices.dropFirst().first { index in
            guard let balance = number(OpenAICodexProvider.creditsLineId, in: quotas[index]),
                  let previous = number(OpenAICodexProvider.creditsLineId, in: quotas[index - 1])
            else {
                return false
            }
            return balance < previous
        }
    }

    private func number(_ id: String, in quota: ProviderQuota) -> Decimal? {
        guard case let .number(value)? = metric(id, in: quota)?.value else { return nil }
        return value
    }

    private func replay(_ fixture: String) throws -> [ProviderQuota] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json"))
        let reads = try JSONDecoder().decode([Read].self, from: Data(contentsOf: url))
        let provider = OpenAICodexProvider()
        return reads.map { provider.map($0.result, receivedAt: Date(timeIntervalSince1970: $0.receivedAt)) }
    }

    private func metric(_ id: String, in quota: ProviderQuota) -> ProviderActivityMetric? {
        quota.activityObservation?.metrics.first { $0.id == id }
    }

    private func states(of lineId: String, in quotas: [ProviderQuota]) -> [AllowanceForecast.State?] {
        let providerId = OpenAICodexProvider.providerId
        var forecaster = AllowanceForecaster()
        return quotas.map { quota in
            if let observation = quota.activityObservation {
                forecaster.record(observation, isStale: false, for: providerId, at: quota.lastUpdated)
            }
            return forecaster.forecasts(for: providerId, at: quota.lastUpdated)[lineId]?.state
        }
    }

    /// Fails on any decrease inside a period, which Core would read as a correction.
    private func periodFirstResets(in quotas: [ProviderQuota]) -> [String: [TimeInterval]] {
        var firstResets: [String: Date] = [:]
        var latestValues: [String: Decimal] = [:]
        var periods: [String: [TimeInterval]] = [:]
        for quota in quotas {
            for metric in quota.activityObservation?.metrics ?? [] {
                guard case let .number(value) = metric.value,
                      case let .fixedPeriod(_, resetsAt, _)? = metric.forecastDescriptor?.accounting
                else {
                    firstResets[metric.id] = nil
                    continue
                }
                let continuesPeriod = firstResets[metric.id].map {
                    AllowanceForecastDescriptor.isSamePeriod(resetsAt: resetsAt, periodResetsAt: $0)
                } ?? false
                if continuesPeriod, let latest = latestValues[metric.id] {
                    XCTAssertGreaterThanOrEqual(value, latest, "\(metric.id) at \(quota.lastUpdated)")
                } else {
                    firstResets[metric.id] = resetsAt
                    periods[metric.id, default: []].append(resetsAt.timeIntervalSince1970)
                }
                latestValues[metric.id] = value
            }
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
