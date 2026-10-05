import Core
@testable import CursorProvider
import XCTest

final class CursorObservationTests: XCTestCase {
    func testActivityObservation_detectsSingleCentChangeUnderLargeAllowance() {
        let provider = CursorProvider()

        let baseline = provider.activityObservation(
            plan: Self.plan(includedSpendCents: 1000),
            onDemand: nil,
            spendLimitUsage: nil
        )
        let advanced = provider.activityObservation(
            plan: Self.plan(includedSpendCents: 1001),
            onDemand: nil,
            spendLimitUsage: nil
        )

        XCTAssertNotEqual(baseline, advanced)
        XCTAssertEqual(advanced.metrics, [
            ProviderActivityMetric(id: "included-usage", kind: .usage, value: .number(Decimal(1001) / 100)),
        ])
    }

    private static func plan(includedSpendCents: Int) -> PlanData {
        PlanData(
            totalPercentUsed: 0.1,
            includedSpend: includedSpendCents,
            limit: 10_000_000,
            bonusSpend: nil,
            autoPercentUsed: nil,
            apiPercentUsed: nil
        )
    }
}
