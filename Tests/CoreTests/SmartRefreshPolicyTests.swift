@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyTests: XCTestCase {
    func testFirstSuccessEstablishesSlowBaseline() {
        var policy = SmartRefreshPolicy()

        let decision = policy.recordSuccess(quota(), for: "provider")

        XCTAssertEqual(decision.classification, .baseline)
        XCTAssertEqual(decision.cadence, .slow)
        XCTAssertTrue(decision.reasons.isEmpty)
    }

    func testSemanticChangesEnterAndSustainFastMode() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider")

        let firstChange = policy.recordSuccess(quota(usage: 20), for: "provider")
        let secondChange = policy.recordSuccess(quota(usage: 30), for: "provider")

        XCTAssertEqual(firstChange.classification, .changed)
        XCTAssertEqual(firstChange.cadence, .fast)
        XCTAssertEqual(firstChange.reasons, [.usage])
        XCTAssertEqual(secondChange.cadence, .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)
    }

    func testThreeUnchangedFastChecksReturnToSlow() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider")
        _ = policy.recordSuccess(quota(usage: 20), for: "provider")

        let firstUnchanged = policy.recordSuccess(quota(usage: 20), for: "provider")

        XCTAssertEqual(firstUnchanged.classification, .unchanged)
        XCTAssertEqual(firstUnchanged.cadence, .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 1)

        let secondUnchanged = policy.recordSuccess(quota(usage: 20), for: "provider")
        XCTAssertEqual(secondUnchanged.cadence, .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 2)

        let thirdUnchanged = policy.recordSuccess(quota(usage: 20), for: "provider")
        XCTAssertEqual(thirdUnchanged.cadence, .slow)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)
    }

    func testChangedFastResultResetsUnchangedCount() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider")
        _ = policy.recordSuccess(quota(usage: 20), for: "provider")
        _ = policy.recordSuccess(quota(usage: 20), for: "provider")

        let decision = policy.recordSuccess(quota(usage: 30), for: "provider")

        XCTAssertEqual(decision.classification, .changed)
        XCTAssertEqual(decision.cadence, .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)
    }

    func testFailurePreservesBaselineAndReturnsToSlow() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider")
        _ = policy.recordSuccess(quota(usage: 20), for: "provider")

        XCTAssertEqual(policy.recordFailure(for: "provider"), .slow)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)

        let unchanged = policy.recordSuccess(quota(usage: 20), for: "provider")
        let changed = policy.recordSuccess(quota(usage: 30), for: "provider")

        XCTAssertEqual(unchanged.classification, .unchanged)
        XCTAssertEqual(unchanged.cadence, .slow)
        XCTAssertEqual(changed.classification, .changed)
        XCTAssertEqual(changed.reasons, [.usage])
    }

    func testPresentationOnlyChangesRemainUnchanged() {
        let base = presentationQuota(isUpdated: false)
        let changedPresentation = presentationQuota(isUpdated: true)
        var policy = SmartRefreshPolicy()

        _ = policy.recordSuccess(base, for: "provider")
        let decision = policy.recordSuccess(changedPresentation, for: "provider")

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
            for: "provider"
        )

        let decision = policy.recordSuccess(
            quota(metrics: [
                metric(id: "credits", kind: .credits, value: twoAndAHalfWithTrailingZero),
                metric(id: "usage", kind: .usage, value: tenWithDecimal),
            ]),
            for: "provider"
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
            for: "provider"
        )

        let decision = policy.recordSuccess(
            quota(metrics: [
                metric(id: "usage", kind: .usage, value: Decimal(20)),
                metric(id: "new-credit", kind: .credits, value: Decimal(8)),
            ]),
            for: "provider"
        )

        XCTAssertEqual(decision.classification, .changed)
        XCTAssertEqual(decision.reasons, [.usage, .credits])
        XCTAssertEqual(decision.cadence, .fast)
    }

    func testKnownAvailabilityTransitionReportsOnlyAvailability() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10, availability: .available), for: "provider")

        let decision = policy.recordSuccess(quota(usage: 10, availability: .unavailable), for: "provider")

        XCTAssertEqual(decision.classification, .changed)
        XCTAssertEqual(decision.reasons, [.availability])
        XCTAssertEqual(decision.cadence, .fast)
    }

    func testUnknownAndAbsentObservationsEstablishBaselinesWithoutActivity() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(observation: nil), for: "provider")

        let initialKnown = policy.recordSuccess(quota(usage: 10, availability: .unknown), for: "provider")
        let knownAvailability = policy.recordSuccess(quota(usage: 10, availability: .available), for: "provider")
        let absent = policy.recordSuccess(quota(observation: nil), for: "provider")
        let restored = policy.recordSuccess(quota(usage: 20, availability: .unavailable), for: "provider")
        let transition = policy.recordSuccess(quota(usage: 20, availability: .available), for: "provider")

        XCTAssertEqual(initialKnown.classification, .unchanged)
        XCTAssertEqual(knownAvailability.classification, .unchanged)
        XCTAssertEqual(absent.classification, .unchanged)
        XCTAssertEqual(restored.classification, .unchanged)
        XCTAssertEqual(transition.classification, .changed)
        XCTAssertEqual(transition.reasons, [.availability])
    }

    func testEmptyObservationsDoNotMasqueradeAsMetricRemovalOrAddition() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider")

        let empty = policy.recordSuccess(quota(metrics: []), for: "provider")
        let restored = policy.recordSuccess(quota(usage: 20), for: "provider")

        XCTAssertEqual(empty.classification, .unchanged)
        XCTAssertEqual(restored.classification, .unchanged)
        XCTAssertEqual(restored.cadence, .slow)
    }

    func testProviderStateIsIsolated() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "first")
        _ = policy.recordSuccess(quota(usage: 10), for: "second")

        let firstDecision = policy.recordSuccess(quota(usage: 20), for: "first")
        let secondDecision = policy.recordSuccess(quota(usage: 10), for: "second")

        XCTAssertEqual(firstDecision.cadence, .fast)
        XCTAssertEqual(secondDecision.cadence, .slow)
        XCTAssertEqual(policy.cadence(for: "second"), .slow)
    }

    private func quota(
        usage: Double = 10,
        availability: ProviderAvailability? = nil,
        metrics: [ProviderActivityMetric]? = nil,
        observation: ProviderActivityObservation? = ProviderActivityObservation(),
        providerName: String = "Provider",
        headline: String = "Headline",
        lines: [UsageLine] = [UsageLine(label: "Usage", percentage: 10)],
        lastUpdated: Date = Date(),
        error: String? = nil,
        isStale: Bool = false,
        peakHoursConfig: PeakHoursConfig? = nil
    ) -> ProviderQuota {
        let resolvedObservation = observation.map { _ in
            ProviderActivityObservation(
                metrics: metrics ?? [metric(id: "usage", kind: .usage, value: Decimal(usage))],
                availability: availability
            )
        }
        return ProviderQuota(
            providerId: "provider",
            providerName: providerName,
            headline: headline,
            lines: lines,
            lastUpdated: lastUpdated,
            error: error,
            isStale: isStale,
            activityObservation: resolvedObservation,
            peakHoursConfig: peakHoursConfig
        )
    }

    private func metric(
        id: String,
        kind: ProviderActivityMetric.Kind,
        value: Decimal
    ) -> ProviderActivityMetric {
        ProviderActivityMetric(id: id, kind: kind, value: .number(value))
    }

    private func presentationQuota(isUpdated: Bool) -> ProviderQuota {
        quota(
            usage: 10,
            providerName: isUpdated ? "Second name" : "First name",
            headline: isUpdated ? "Second headline" : "First headline",
            lines: presentationLines(isUpdated: isUpdated),
            lastUpdated: Date(timeIntervalSince1970: isUpdated ? 2 : 1),
            error: isUpdated ? nil : "Old error",
            isStale: !isUpdated,
            peakHoursConfig: presentationPeakHours(isUpdated: isUpdated)
        )
    }

    private func presentationLines(isUpdated: Bool) -> [UsageLine] {
        if isUpdated {
            return [
                UsageLine(
                    label: "Localized usage",
                    used: 9,
                    total: 100,
                    percentage: 90,
                    unit: "tokens",
                    resetDate: Date(timeIntervalSince1970: 200),
                    details: [
                        UsageDetail(label: "B", value: "2"),
                        UsageDetail(label: "A", value: "updated"),
                    ]
                ),
                UsageLine(label: "Additional line", percentage: 50),
            ]
        }
        return [
            UsageLine(
                label: "Usage",
                used: 1,
                total: 10,
                percentage: 10,
                unit: "requests",
                resetDate: Date(timeIntervalSince1970: 100),
                details: [UsageDetail(label: "A", value: "1")]
            ),
        ]
    }

    private func presentationPeakHours(isUpdated: Bool) -> PeakHoursConfig {
        PeakHoursConfig(
            timeZone: TimeZone(identifier: isUpdated ? "Asia/Shanghai" : "UTC"),
            peakStartHour: isUpdated ? 14 : 1,
            peakEndHour: isUpdated ? 18 : 2,
            peakMultiplier: isUpdated ? 4 : 3,
            offPeakMultiplier: isUpdated ? 1 : 2
        )
    }
}
