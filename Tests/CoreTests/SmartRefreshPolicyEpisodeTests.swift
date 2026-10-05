@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyEpisodeTests: SmartRefreshPolicyTestCase {
    private let longWindow: TimeInterval = 900

    func testWideningTheQuietWindowAfterNaturalEndRestartsACappedEpisode() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 0),
            for: "provider",
            at: 0,
            quietWindow: longWindow,
            canInvokeInference: true
        )
        _ = policy.recordSuccess(
            quota(usage: 1),
            for: "provider",
            at: 0,
            quietWindow: longWindow,
            canInvokeInference: true
        )

        policy.advance(for: "provider", at: 400, quietWindow: 120)
        policy.advance(for: "provider", at: 400, quietWindow: longWindow)
        _ = policy.recordSuccess(
            quota(usage: 2),
            for: "provider",
            at: 500,
            quietWindow: longWindow,
            canInvokeInference: true
        )

        XCTAssertEqual(policy.cadence(for: "provider", at: 999, quietWindow: longWindow), .fast)

        policy.advance(for: "provider", at: 1000, quietWindow: longWindow)
        XCTAssertEqual(policy.cadence(for: "provider", at: 1000, quietWindow: longWindow), .slow)
    }

    func testLateAdvancementAfterNaturalEndDoesNotInventALockout() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 0),
            for: "provider",
            at: 0,
            quietWindow: 120,
            canInvokeInference: true
        )
        _ = policy.recordSuccess(
            quota(usage: 1),
            for: "provider",
            at: 0,
            quietWindow: 120,
            canInvokeInference: true
        )

        policy.advance(for: "provider", at: 700, quietWindow: 120)
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: 120), .slow)

        let decision = policy.recordSuccess(
            quota(usage: 2),
            for: "provider",
            at: 700,
            quietWindow: 120,
            canInvokeInference: true
        )
        XCTAssertEqual(decision.classification, .changed)
        XCTAssertEqual(decision.cadence, .fast)
    }

    func testFailureAfterACapCrossedDuringAnExtensionKeepsTheLockout() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 0),
            for: "provider",
            at: 0,
            quietWindow: longWindow,
            canInvokeInference: true
        )
        _ = policy.recordSuccess(
            quota(usage: 1),
            for: "provider",
            at: 0,
            quietWindow: longWindow,
            canInvokeInference: true
        )
        policy.recordExtension(for: "provider", duration: 900, at: 0)

        _ = policy.recordFailure(for: "provider", at: 610, quietWindow: longWindow)

        XCTAssertNil(policy.extensionDeadline(for: "provider"))
        XCTAssertEqual(
            policy.recordActivityHint(
                for: "provider",
                at: 670,
                quietWindow: longWindow,
                canInvokeInference: true
            ),
            .slow
        )
        XCTAssertEqual(policy.cadence(for: "provider", at: 1499, quietWindow: longWindow), .slow)
    }

    func testPhaseBoundaryIncludesTheUnderlyingCapDuringAnExtension() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 0),
            for: "provider",
            at: 0,
            quietWindow: longWindow,
            canInvokeInference: true
        )
        _ = policy.recordSuccess(
            quota(usage: 1),
            for: "provider",
            at: 0,
            quietWindow: longWindow,
            canInvokeInference: true
        )
        policy.recordExtension(for: "provider", duration: 900, at: 0)

        XCTAssertEqual(policy.nextPhaseBoundary(for: "provider", at: 0, quietWindow: longWindow), 600)
    }

    func testOmittedMetricRetainsTheBaselineWithoutManufacturingAChange() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(metrics: [
                metric(id: "five-hour-usage", kind: .usage, value: 1000),
                metric(id: "weekly-usage", kind: .usage, value: 5),
            ]),
            for: "provider",
            at: 0,
            quietWindow: quietWindow
        )

        let omitted = policy.recordSuccess(
            quota(metrics: [metric(id: "five-hour-usage", kind: .usage, value: 1000)]),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )
        XCTAssertEqual(omitted.classification, .unchanged)

        let restored = policy.recordSuccess(
            quota(metrics: [
                metric(id: "five-hour-usage", kind: .usage, value: 1000),
                metric(id: "weekly-usage", kind: .usage, value: 5),
            ]),
            for: "provider",
            at: 20,
            quietWindow: quietWindow
        )
        XCTAssertEqual(restored.classification, .unchanged)
    }
}
