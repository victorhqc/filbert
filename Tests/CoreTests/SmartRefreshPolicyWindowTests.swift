@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyWindowTests: SmartRefreshPolicyTestCase {
    func testSemanticChangesEnterAndSustainFastMode() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)

        let firstChange = policy.recordSuccess(
            quota(usage: 20),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )
        let secondChange = policy.recordSuccess(
            quota(usage: 30),
            for: "provider",
            at: 20,
            quietWindow: quietWindow
        )

        XCTAssertEqual(firstChange.classification, .changed)
        XCTAssertEqual(firstChange.cadence, .fast)
        XCTAssertEqual(firstChange.reasons, [.usage])
        XCTAssertEqual(secondChange.classification, .changed)
        XCTAssertEqual(secondChange.cadence, .fast)
    }

    func testUnchangedResultsDoNotRenewTheActivityWindow() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 10, quietWindow: quietWindow)

        let stillFast = policy.recordSuccess(
            quota(usage: 20),
            for: "provider",
            at: 200,
            quietWindow: quietWindow
        )
        XCTAssertEqual(stillFast.classification, .unchanged)
        XCTAssertEqual(stillFast.cadence, .fast)

        let cooldown = policy.recordSuccess(
            quota(usage: 20),
            for: "provider",
            at: 400,
            quietWindow: quietWindow
        )
        XCTAssertEqual(cooldown.cadence, .cooldown)

        let slow = policy.recordSuccess(
            quota(usage: 20),
            for: "provider",
            at: 700,
            quietWindow: quietWindow
        )
        XCTAssertEqual(slow.cadence, .slow)
    }

    func testNumberOfUnchangedResultsDoesNotEndFastMode() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)

        for step in 1 ... 20 {
            let decision = policy.recordSuccess(
                quota(usage: 20),
                for: "provider",
                at: TimeInterval(step),
                quietWindow: quietWindow
            )
            XCTAssertEqual(decision.classification, .unchanged)
            XCTAssertEqual(decision.cadence, .fast)
        }
    }

    func testSemanticChangeDuringCooldownRestoresFastMode() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)

        let cooldown = policy.recordSuccess(
            quota(usage: 20),
            for: "provider",
            at: 400,
            quietWindow: quietWindow
        )
        XCTAssertEqual(cooldown.cadence, .cooldown)

        let changed = policy.recordSuccess(
            quota(usage: 30),
            for: "provider",
            at: 420,
            quietWindow: quietWindow
        )
        XCTAssertEqual(changed.classification, .changed)
        XCTAssertEqual(changed.cadence, .fast)
        XCTAssertEqual(policy.cadence(for: "provider", at: 500, quietWindow: quietWindow), .fast)
    }

    func testExactQuietWindowBoundaries() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)

        XCTAssertEqual(policy.cadence(for: "provider", at: 299.999, quietWindow: quietWindow), .fast)
        XCTAssertEqual(policy.cadence(for: "provider", at: 300, quietWindow: quietWindow), .cooldown)
        XCTAssertEqual(policy.cadence(for: "provider", at: 599.999, quietWindow: quietWindow), .cooldown)
        XCTAssertEqual(policy.cadence(for: "provider", at: 600, quietWindow: quietWindow), .slow)
    }

    func testNextPhaseBoundaryTracksTheActivityTime() {
        var policy = SmartRefreshPolicy()
        XCTAssertNil(policy.nextPhaseBoundary(for: "provider", at: 0, quietWindow: quietWindow))

        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)

        XCTAssertEqual(policy.nextPhaseBoundary(for: "provider", at: 100, quietWindow: quietWindow), 300)
        XCTAssertEqual(policy.nextPhaseBoundary(for: "provider", at: 400, quietWindow: quietWindow), 600)
        XCTAssertNil(policy.nextPhaseBoundary(for: "provider", at: 700, quietWindow: quietWindow))
    }

    func testActivityHintStartsAWindowWithoutASemanticChange() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        XCTAssertEqual(policy.cadence(for: "provider", at: 0, quietWindow: quietWindow), .slow)

        XCTAssertEqual(policy.recordActivityHint(for: "provider", at: 100), .fast)
        XCTAssertEqual(policy.cadence(for: "provider", at: 399, quietWindow: quietWindow), .fast)
        XCTAssertEqual(policy.cadence(for: "provider", at: 400, quietWindow: quietWindow), .cooldown)
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .slow)
    }

    func testQuietWindowDurationDrivesThePhaseBoundaries() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: 120)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: 120)

        XCTAssertEqual(policy.cadence(for: "provider", at: 119, quietWindow: 120), .fast)
        XCTAssertEqual(policy.cadence(for: "provider", at: 120, quietWindow: 120), .cooldown)
        XCTAssertEqual(policy.cadence(for: "provider", at: 240, quietWindow: 120), .slow)

        XCTAssertEqual(policy.cadence(for: "provider", at: 240, quietWindow: 300), .fast)
    }

    func testFailureClearsTheActivityWindowAndPreservesBaseline() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)

        XCTAssertEqual(policy.recordFailure(for: "provider"), .slow)
        XCTAssertEqual(policy.cadence(for: "provider", at: 0, quietWindow: quietWindow), .slow)

        let unchanged = policy.recordSuccess(
            quota(usage: 20),
            for: "provider",
            at: 10,
            quietWindow: quietWindow
        )
        let changed = policy.recordSuccess(
            quota(usage: 30),
            for: "provider",
            at: 20,
            quietWindow: quietWindow
        )

        XCTAssertEqual(unchanged.classification, .unchanged)
        XCTAssertEqual(unchanged.cadence, .slow)
        XCTAssertEqual(changed.classification, .changed)
        XCTAssertEqual(changed.reasons, [.usage])
    }
}
