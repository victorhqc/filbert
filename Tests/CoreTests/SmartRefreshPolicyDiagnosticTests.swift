@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyDiagnosticTests: SmartRefreshPolicyTestCase {
    func testChangedDecisionReportsOnlySafeReasonCategories() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(metrics: [
                metric(id: "total-balance-cny", kind: .credits, value: Decimal(110)),
            ]),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let decision = policy.recordSuccess(
            quota(metrics: [
                metric(id: "total-balance-cny", kind: .credits, value: Decimal(90)),
            ]),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )

        XCTAssertEqual(decision.classification, .changed)
        XCTAssertEqual(decision.cadence, .fast)
        XCTAssertEqual(decision.reasons, [.credits])
        XCTAssertEqual(Set(SmartRefreshPolicy.ChangeReason.allCases), [.usage, .credits, .availability])
    }

    func testExtensionExpiringDuringInferenceLockoutResumesSlowCadence() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 0),
            for: "provider",
            at: 0,
            quietWindow: quietWindow,
            canInvokeInference: true
        )
        _ = policy.recordSuccess(
            quota(usage: 1),
            for: "provider",
            at: 0,
            quietWindow: quietWindow,
            canInvokeInference: true
        )
        policy.advance(for: "provider", at: 600, quietWindow: quietWindow)

        policy.recordExtension(for: "provider", duration: 120, at: 600)
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .fast)

        policy.advance(for: "provider", at: 720, quietWindow: quietWindow)
        XCTAssertNil(policy.extensionDeadline(for: "provider"))
        XCTAssertEqual(policy.cadence(for: "provider", at: 720, quietWindow: quietWindow), .slow)
    }
}
