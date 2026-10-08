@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyDescriptorTests: SmartRefreshPolicyTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testDescriptorTimingAloneRemainsUnchanged() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(value: 10, writtenAt: origin), for: "provider", at: 0, quietWindow: quietWindow)

        let decision = policy.recordSuccess(
            quota(value: 10, writtenAt: origin.addingTimeInterval(60)),
            for: "provider",
            at: 60,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .unchanged)
    }

    func testChangedValueWithADescriptorIsStillAChange() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(value: 10, writtenAt: origin), for: "provider", at: 0, quietWindow: quietWindow)

        let decision = policy.recordSuccess(
            quota(value: 11, writtenAt: origin.addingTimeInterval(60)),
            for: "provider",
            at: 60,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .changed)
    }

    private func quota(value: Decimal, writtenAt: Date) -> ProviderQuota {
        quota(
            metrics: [
                ProviderActivityMetric(
                    id: "usage",
                    kind: .usage,
                    value: .number(value),
                    forecastDescriptor: AllowanceForecastDescriptor(
                        accounting: .fixedPeriod(limit: 100, resetsAt: origin.addingTimeInterval(3600)),
                        unit: .percentagePoints,
                        resolution: 1,
                        timing: .source(writtenAt),
                        usageLineId: "usage"
                    )
                ),
            ],
            freshness: .fresh,
            lastUpdated: writtenAt
        )
    }
}
