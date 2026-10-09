@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyDescriptorTests: SmartRefreshPolicyTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testDescriptorTimingAloneRemainsUnchanged() {
        XCTAssertEqual(classify(after: descriptorQuota(writtenAt: origin.addingTimeInterval(60))), .unchanged)
    }

    func testResetJitterInsideTheToleranceRemainsUnchanged() {
        let jittered = descriptorQuota(resetsAt: defaultReset.addingTimeInterval(0.4))

        XCTAssertEqual(classify(after: jittered), .unchanged)
    }

    func testChangedValueWithADescriptorIsStillAChange() {
        XCTAssertEqual(classify(after: descriptorQuota(value: 11)), .changed)
    }

    func testNewLimitIsAChange() {
        XCTAssertEqual(classify(after: descriptorQuota(limit: 200)), .changed)
    }

    func testNewPeriodIsAChange() {
        let nextPeriod = descriptorQuota(resetsAt: defaultReset.addingTimeInterval(5 * 60 * 60))

        XCTAssertEqual(classify(after: nextPeriod), .changed)
    }

    func testWithdrawnDescriptorIsAChange() {
        XCTAssertEqual(classify(after: descriptorQuota(hasDescriptor: false)), .changed)
    }

    private var defaultReset: Date {
        origin.addingTimeInterval(3600)
    }

    private func classify(after next: ProviderQuota) -> SmartRefreshPolicy.Classification {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(descriptorQuota(), for: "provider", at: 0, quietWindow: quietWindow)
        return policy.recordSuccess(next, for: "provider", at: 60, quietWindow: quietWindow).classification
    }

    private func descriptorQuota(
        value: Decimal = 10,
        limit: Decimal = 100,
        resetsAt: Date? = nil,
        writtenAt: Date? = nil,
        hasDescriptor: Bool = true
    ) -> ProviderQuota {
        let writtenAt = writtenAt ?? origin
        let descriptor = AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: limit, resetsAt: resetsAt ?? defaultReset),
            unit: .percentagePoints,
            resolution: 1,
            timing: .source(writtenAt),
            usageLineId: "usage"
        )
        return quota(
            metrics: [
                ProviderActivityMetric(
                    id: "usage",
                    kind: .usage,
                    value: .number(value),
                    forecastDescriptor: hasDescriptor ? descriptor : nil
                ),
            ],
            freshness: .fresh,
            lastUpdated: writtenAt
        )
    }
}
