@testable import Core
import Foundation
import XCTest

final class AllowanceForecastContractTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testOptInFieldsDefaultToNil() {
        let metric = ProviderActivityMetric(id: "usage", kind: .usage, value: .number(1))
        let line = UsageLine(label: "Usage", percentage: 1)
        let quota = ProviderQuota(
            providerId: "provider",
            providerName: "Provider",
            headline: "1%",
            lines: [line],
            lastUpdated: origin
        )

        XCTAssertNil(metric.forecastDescriptor)
        XCTAssertNil(line.id)
        XCTAssertNil(line.limitGroup)
        XCTAssertNil(quota.headlineUsageLineId)
    }

    func testSmartRefreshIgnoresDescriptorTimingWhenTheValueIsUnchanged() {
        var policy = SmartRefreshPolicy()
        policy.recordSuccess(quota(value: 10, writtenAt: origin), for: "provider", at: 0, quietWindow: 300)

        let decision = policy.recordSuccess(
            quota(value: 10, writtenAt: origin.addingTimeInterval(60)),
            for: "provider",
            at: 60,
            quietWindow: 300
        )

        XCTAssertEqual(decision.classification, .unchanged)
    }

    func testSmartRefreshStillDetectsAChangedValue() {
        var policy = SmartRefreshPolicy()
        policy.recordSuccess(quota(value: 10, writtenAt: origin), for: "provider", at: 0, quietWindow: 300)

        let decision = policy.recordSuccess(
            quota(value: 11, writtenAt: origin.addingTimeInterval(60)),
            for: "provider",
            at: 60,
            quietWindow: 300
        )

        XCTAssertEqual(decision.classification, .changed)
    }

    private func quota(value: Decimal, writtenAt: Date) -> ProviderQuota {
        ProviderQuota(
            providerId: "provider",
            providerName: "Provider",
            headline: "\(value)%",
            lines: [],
            lastUpdated: writtenAt,
            activityObservation: ProviderActivityObservation(
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
                freshness: .fresh
            )
        )
    }
}
