@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyTests: SmartRefreshPolicyTestCase {
    func testFirstSuccessEstablishesSlowBaseline() {
        var policy = SmartRefreshPolicy()

        let decision = policy.recordSuccess(quota(), for: "provider", at: 0, quietWindow: quietWindow)

        XCTAssertEqual(decision.classification, .baseline)
        XCTAssertEqual(decision.cadence, .slow)
        XCTAssertTrue(decision.reasons.isEmpty)
    }

    func testPresentationOnlyChangesRemainUnchanged() {
        let base = presentationQuota(isUpdated: false)
        let changedPresentation = presentationQuota(isUpdated: true)
        var policy = SmartRefreshPolicy()

        _ = policy.recordSuccess(base, for: "provider", at: 0, quietWindow: quietWindow)
        let decision = policy.recordSuccess(
            changedPresentation,
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .unchanged)
        XCTAssertEqual(decision.cadence, .slow)
        XCTAssertTrue(decision.reasons.isEmpty)
    }

    func testMetricReorderingAndEquivalentNumericFormattingRemainUnchanged() throws {
        let ten = try XCTUnwrap(Decimal(string: "10"))
        let tenWithDecimal = try XCTUnwrap(Decimal(string: "10.0"))
        let twoAndAHalf = try XCTUnwrap(Decimal(string: "2.50"))
        let twoAndAHalfWithTrailingZero = try XCTUnwrap(Decimal(string: "2.500"))
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(metrics: [
                metric(id: "usage", kind: .usage, value: ten),
                metric(id: "credits", kind: .credits, value: twoAndAHalf),
            ]),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let decision = policy.recordSuccess(
            quota(metrics: [
                metric(id: "credits", kind: .credits, value: twoAndAHalfWithTrailingZero),
                metric(id: "usage", kind: .usage, value: tenWithDecimal),
            ]),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .unchanged)
        XCTAssertEqual(decision.cadence, .slow)
    }

    func testUsageAndCreditChangesReportBothReasonsIncludingMetricRemovalAndAddition() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(metrics: [
                metric(id: "usage", kind: .usage, value: Decimal(10)),
                metric(id: "old-credit", kind: .credits, value: Decimal(5)),
            ]),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let decision = policy.recordSuccess(
            quota(metrics: [
                metric(id: "usage", kind: .usage, value: Decimal(20)),
                metric(id: "new-credit", kind: .credits, value: Decimal(8)),
            ]),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .changed)
        XCTAssertEqual(decision.reasons, [.usage, .credits])
        XCTAssertEqual(decision.cadence, .fast)
    }

    func testKnownAvailabilityTransitionReportsOnlyAvailability() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 10, availability: .available),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let decision = policy.recordSuccess(
            quota(usage: 10, availability: .unavailable),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .changed)
        XCTAssertEqual(decision.reasons, [.availability])
        XCTAssertEqual(decision.cadence, .fast)
    }

    func testAbsentObservationRetainsTheBaselineWithoutManufacturingAChange() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)

        let absent = policy.recordSuccess(quota(observation: nil), for: "provider", at: 0, quietWindow: quietWindow)
        XCTAssertEqual(absent.classification, .unchanged)
        XCTAssertEqual(absent.cadence, .slow)

        let unchanged = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        XCTAssertEqual(unchanged.classification, .unchanged)

        let changed = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)
        XCTAssertEqual(changed.classification, .changed)
        XCTAssertEqual(changed.reasons, [.usage])
    }

    func testAbsentObservationDoesNotEstablishABaseline() {
        var policy = SmartRefreshPolicy()

        let absent = policy.recordSuccess(quota(observation: nil), for: "provider", at: 0, quietWindow: quietWindow)
        XCTAssertEqual(absent.classification, .unchanged)
        XCTAssertEqual(absent.cadence, .slow)

        let baseline = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        XCTAssertEqual(baseline.classification, .baseline)
    }

    func testUnknownAndAbsentAvailabilityDoNotManufactureChanges() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 10, availability: .unknown),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let known = policy.recordSuccess(
            quota(usage: 10, availability: .available),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )
        let absentAvailability = policy.recordSuccess(
            quota(usage: 10),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )
        let transition = policy.recordSuccess(
            quota(usage: 10, availability: .unavailable),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        XCTAssertEqual(known.classification, .unchanged)
        XCTAssertEqual(absentAvailability.classification, .unchanged)
        XCTAssertEqual(transition.classification, .changed)
        XCTAssertEqual(transition.reasons, [.availability])
    }

    func testEmptyMetricsRetainTheBaselineWithoutMasqueradingAsRemovalOrAddition() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)

        let empty = policy.recordSuccess(quota(metrics: []), for: "provider", at: 0, quietWindow: quietWindow)
        let restored = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)

        XCTAssertEqual(empty.classification, .unchanged)
        XCTAssertEqual(restored.classification, .changed)
        XCTAssertEqual(restored.reasons, [.usage])
    }

    func testProviderKnownStaleResultDoesNotRenewOrReplaceTheBaseline() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 10, quietWindow: quietWindow)

        let stale = policy.recordSuccess(
            quota(usage: 9, freshness: .stale),
            for: "provider",
            at: 700,
            quietWindow: quietWindow
        )
        let restored = policy.recordSuccess(quota(usage: 20), for: "provider", at: 700, quietWindow: quietWindow)

        XCTAssertEqual(stale.classification, .unchanged)
        XCTAssertEqual(stale.cadence, .slow)
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .slow)
        XCTAssertEqual(restored.classification, .unchanged)
    }

    func testStaleResultDoesNotEstablishABaseline() {
        var policy = SmartRefreshPolicy()

        let stale = policy.recordSuccess(
            quota(usage: 10, freshness: .stale),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )
        let baseline = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)

        XCTAssertEqual(stale.classification, .unchanged)
        XCTAssertEqual(baseline.classification, .baseline)
    }

    func testUnknownAndFreshObservationsPermitSemanticComparison() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 10, freshness: .unknown),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let unknownChange = policy.recordSuccess(
            quota(usage: 20, freshness: .unknown),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )
        let freshChange = policy.recordSuccess(
            quota(usage: 30, freshness: .fresh),
            for: "provider",
            at: 20,
            quietWindow: quietWindow
        )

        XCTAssertEqual(unknownChange.classification, .changed)
        XCTAssertEqual(unknownChange.cadence, .fast)
        XCTAssertEqual(freshChange.classification, .changed)
        XCTAssertEqual(freshChange.cadence, .fast)
    }

    func testChangedFetchTimestampAloneDoesNotRenewActivity() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 10, lastUpdated: Date(timeIntervalSince1970: 1)),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let decision = policy.recordSuccess(
            quota(usage: 10, lastUpdated: Date(timeIntervalSince1970: 2)),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .unchanged)
        XCTAssertEqual(decision.cadence, .slow)
    }

    func testProviderStateIsIsolated() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "first", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 10), for: "second", at: 0, quietWindow: quietWindow)

        let firstDecision = policy.recordSuccess(quota(usage: 20), for: "first", at: 10, quietWindow: quietWindow)
        let secondDecision = policy.recordSuccess(quota(usage: 10), for: "second", at: 10, quietWindow: quietWindow)

        XCTAssertEqual(firstDecision.cadence, .fast)
        XCTAssertEqual(secondDecision.cadence, .slow)
        XCTAssertEqual(policy.cadence(for: "second", at: 10, quietWindow: quietWindow), .slow)
    }
}
