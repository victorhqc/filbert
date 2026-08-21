@testable import App
import Core
import Foundation
import XCTest

final class MenuBarProviderActivityPolicyTests: XCTestCase {
    private let providerId = "provider"
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testFirstObservationEstablishesBaselineWithoutAwardingPoints() {
        var policy = MenuBarProviderActivityPolicy()

        XCTAssertFalse(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([usage("window", 1)]),
                at: start
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 0)
        XCTAssertEqual(policy.baselineProviderIds, [providerId])
    }

    func testAbsentAndEmptyObservationsRemainConservative() {
        var policy = MenuBarProviderActivityPolicy()

        _ = policy.recordSuccessfulResult(for: providerId, observation: nil, at: start)
        _ = policy.recordSuccessfulResult(
            for: providerId,
            observation: observation([]),
            at: start.addingTimeInterval(1)
        )
        _ = policy.recordSuccessfulResult(
            for: providerId,
            observation: observation([usage("window", 1)]),
            at: start.addingTimeInterval(2)
        )

        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 0)
    }

    func testUnchangedValuesAwardNoPoints() {
        var policy = policyWithBaseline(observation([usage("window", 10), credits("balance", 20)]))

        XCTAssertFalse(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([credits("balance", 20), usage("window", 10)]),
                at: start.addingTimeInterval(60)
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 0)
    }

    func testUsageIncreaseAwardsTenPoints() {
        var policy = policyWithBaseline(observation([usage("window", 10)]))

        XCTAssertTrue(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([usage("window", 11)]),
                at: start
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 10)
    }

    func testUsageDecreaseAwardsNoPoints() {
        var policy = policyWithBaseline(observation([usage("window", 10)]))

        XCTAssertFalse(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([usage("window", 9)]),
                at: start
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 0)
    }

    func testCreditDecreaseAwardsTenPoints() {
        var policy = policyWithBaseline(observation([credits("balance", 20)]))

        XCTAssertTrue(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([credits("balance", 19)]),
                at: start
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 10)
    }

    func testCreditIncreaseAwardsNoPoints() {
        var policy = policyWithBaseline(observation([credits("balance", 20)]))

        XCTAssertFalse(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([credits("balance", 21)]),
                at: start
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 0)
    }

    func testSeveralQualifyingMetricsAwardOneConsumptionEvent() {
        var policy = policyWithBaseline(
            observation([usage("window", 10), usage("weekly", 20), credits("balance", 20)])
        )

        XCTAssertTrue(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([usage("weekly", 21), credits("balance", 19), usage("window", 11)]),
                at: start
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 10)
    }

    func testAddedRemovedDiscreteAndAvailabilityChangesAwardNoPoints() {
        var policy = policyWithBaseline(
            observation(
                [usage("window", 10), discrete("mode", "ready")],
                availability: .available
            )
        )

        _ = policy.recordSuccessfulResult(
            for: providerId,
            observation: observation(
                [usage("window", 10), usage("new", 100), discrete("mode", "busy")],
                availability: .unavailable
            ),
            at: start
        )
        _ = policy.recordSuccessfulResult(
            for: providerId,
            observation: observation([usage("window", 10)]),
            at: start
        )

        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 0)
    }

    func testMetricsMatchByStableIdAndKindRatherThanArrayPosition() {
        var policy = policyWithBaseline(
            observation([usage("window", 10), credits("balance", 20)])
        )

        XCTAssertTrue(
            policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([credits("balance", 19), usage("window", 11)]),
                at: start
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 10)
    }

    func testFastEntryAwardsThirtyPointsOnlyOnceAndExitPreservesScore() {
        var policy = MenuBarProviderActivityPolicy()

        XCTAssertTrue(policy.recordFastRefreshState(true, for: providerId, at: start))
        XCTAssertFalse(policy.recordFastRefreshState(true, for: providerId, at: start))
        XCTAssertFalse(
            policy.recordFastRefreshState(
                false,
                for: providerId,
                at: start.addingTimeInterval(60)
            )
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start.addingTimeInterval(60)), 29)
    }

    func testConsumptionAndFastEntryAwardsCombine() {
        var policy = policyWithBaseline(observation([usage("window", 10)]))

        _ = policy.recordSuccessfulResult(
            for: providerId,
            observation: observation([usage("window", 11)]),
            at: start
        )
        _ = policy.recordFastRefreshState(true, for: providerId, at: start)

        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 40)
    }

    func testScoreIsCappedAtSixtyPoints() {
        var policy = policyWithBaseline(observation([usage("window", 0)]))

        for value in 1 ... 8 {
            _ = policy.recordSuccessfulResult(
                for: providerId,
                observation: observation([usage("window", value)]),
                at: start
            )
        }

        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 60)
    }

    func testScoreDecaysLinearlyAndAwardsResolveTheDecayedValue() {
        var policy = policyWithBaseline(observation([usage("window", 0)]))
        _ = policy.recordFastRefreshState(true, for: providerId, at: start)

        XCTAssertEqual(
            policy.effectiveScore(for: providerId, at: start.addingTimeInterval(30)),
            29.5,
            accuracy: 0.0001
        )

        _ = policy.recordSuccessfulResult(
            for: providerId,
            observation: observation([usage("window", 1)]),
            at: start.addingTimeInterval(1800)
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start.addingTimeInterval(1800)), 10)
    }

    func testExactZeroAndLongElapsedScoresAreRemovedByResolution() {
        var policy = MenuBarProviderActivityPolicy()
        _ = policy.recordFastRefreshState(true, for: providerId, at: start)

        XCTAssertEqual(policy.resolve(at: start.addingTimeInterval(1800)), [:])
        XCTAssertTrue(policy.activeScoreProviderIds.isEmpty)
        XCTAssertNil(policy.nextExpirationDate(at: start.addingTimeInterval(1800)))
    }

    func testClockMovingBackwardDoesNotIncreaseScore() {
        var policy = MenuBarProviderActivityPolicy()
        _ = policy.recordFastRefreshState(true, for: providerId, at: start)

        XCTAssertEqual(
            policy.effectiveScore(for: providerId, at: start.addingTimeInterval(-3600)),
            30
        )
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 30)
    }

    func testResetRemovesBaselineScoreAndFastState() {
        var policy = policyWithBaseline(observation([usage("window", 0)]))
        _ = policy.recordSuccessfulResult(
            for: providerId,
            observation: observation([usage("window", 1)]),
            at: start
        )
        _ = policy.recordFastRefreshState(true, for: providerId, at: start)

        policy.reset(for: providerId)

        XCTAssertTrue(policy.baselineProviderIds.isEmpty)
        XCTAssertTrue(policy.activeScoreProviderIds.isEmpty)
        XCTAssertFalse(policy.recordFastRefreshState(false, for: providerId, at: start))
        XCTAssertTrue(policy.recordFastRefreshState(true, for: providerId, at: start))
        XCTAssertEqual(policy.effectiveScore(for: providerId, at: start), 30)
    }

    private func policyWithBaseline(_ observation: ProviderActivityObservation) -> MenuBarProviderActivityPolicy {
        var policy = MenuBarProviderActivityPolicy()
        _ = policy.recordSuccessfulResult(for: providerId, observation: observation, at: start)
        return policy
    }

    private func observation(
        _ metrics: [ProviderActivityMetric],
        availability: ProviderAvailability? = nil
    ) -> ProviderActivityObservation {
        ProviderActivityObservation(metrics: metrics, availability: availability)
    }

    private func usage(_ id: String, _ value: Int) -> ProviderActivityMetric {
        ProviderActivityMetric(id: id, kind: .usage, value: .number(Decimal(value)))
    }

    private func credits(_ id: String, _ value: Int) -> ProviderActivityMetric {
        ProviderActivityMetric(id: id, kind: .credits, value: .number(Decimal(value)))
    }

    private func discrete(_ id: String, _ value: String) -> ProviderActivityMetric {
        ProviderActivityMetric(id: id, kind: .usage, value: .discrete(value))
    }
}
