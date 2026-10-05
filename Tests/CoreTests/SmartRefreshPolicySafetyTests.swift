@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicySafetyTests: SmartRefreshPolicyTestCase {
    // MARK: - Explicit extension

    func testExtensionOverridesCadenceUntilItsDeadline() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        policy.recordExtension(for: "provider", duration: 900, at: 0)

        XCTAssertEqual(policy.nextPhaseBoundary(for: "provider", at: 0, quietWindow: quietWindow), 900)
        XCTAssertEqual(policy.cadence(for: "provider", at: 899, quietWindow: quietWindow), .fast)
        XCTAssertEqual(policy.cadence(for: "provider", at: 900, quietWindow: quietWindow), .slow)
    }

    func testLaterExtensionSelectionReplacesTheDeadline() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)

        policy.recordExtension(for: "provider", duration: 900, at: 0)
        policy.recordExtension(for: "provider", duration: 900, at: 100)

        XCTAssertEqual(policy.extensionDeadline(for: "provider"), 1000)
    }

    func testStopExtensionResumesTheAutomaticActivityTime() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        _ = policy.recordSuccess(quota(usage: 20), for: "provider", at: 0, quietWindow: quietWindow)
        policy.recordExtension(for: "provider", duration: 900, at: 0)

        policy.stopExtension(for: "provider")

        XCTAssertNil(policy.extensionDeadline(for: "provider"))
        XCTAssertEqual(policy.cadence(for: "provider", at: 400, quietWindow: quietWindow), .cooldown)
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .slow)
    }

    func testExtensionAloneDoesNotManufactureActivity() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        policy.recordExtension(for: "provider", duration: 900, at: 0)

        policy.stopExtension(for: "provider")

        XCTAssertEqual(policy.cadence(for: "provider", at: 0, quietWindow: quietWindow), .slow)
    }

    func testFailureClearsTheExtensionDeadline() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 10), for: "provider", at: 0, quietWindow: quietWindow)
        policy.recordExtension(for: "provider", duration: 900, at: 0)

        XCTAssertEqual(
            policy.recordFailure(for: "provider", at: 0, quietWindow: quietWindow),
            .slow
        )
        XCTAssertNil(policy.extensionDeadline(for: "provider"))
        XCTAssertEqual(policy.cadence(for: "provider", at: 10, quietWindow: quietWindow), .slow)
    }

    // MARK: - Inference episode cap and lockout

    func testInferenceEpisodeCapEndsFastModeDespiteOngoingChanges() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(
            quota(usage: 0),
            for: "provider",
            at: 0,
            quietWindow: quietWindow,
            canInvokeInference: true
        )

        var usage = 0.0
        for step in stride(from: 0.0, through: 500, by: 100) {
            usage += 1
            _ = policy.recordSuccess(
                quota(usage: usage),
                for: "provider",
                at: step,
                quietWindow: quietWindow,
                canInvokeInference: true
            )
        }
        XCTAssertEqual(policy.cadence(for: "provider", at: 599, quietWindow: quietWindow), .fast)

        usage += 1
        let capped = policy.recordSuccess(
            quota(usage: usage),
            for: "provider",
            at: 600,
            quietWindow: quietWindow,
            canInvokeInference: true
        )

        XCTAssertEqual(capped.classification, .changed)
        XCTAssertEqual(capped.cadence, .slow)
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .slow)
    }

    func testEpisodeStartDoesNotRenewWithActivity() {
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
        _ = policy.recordSuccess(
            quota(usage: 2),
            for: "provider",
            at: 500,
            quietWindow: quietWindow,
            canInvokeInference: true
        )

        XCTAssertEqual(policy.cadence(for: "provider", at: 599, quietWindow: quietWindow), .fast)

        policy.advance(for: "provider", at: 600, quietWindow: quietWindow)
        XCTAssertEqual(policy.cadence(for: "provider", at: 600, quietWindow: quietWindow), .slow)
    }

    func testLockoutUpdatesTheBaselineWithoutRenewingTheWindow() {
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
        XCTAssertEqual(policy.cadence(for: "provider", at: 600, quietWindow: quietWindow), .slow)

        let duringLockout = policy.recordSuccess(
            quota(usage: 2),
            for: "provider",
            at: 700,
            quietWindow: quietWindow,
            canInvokeInference: true
        )
        XCTAssertEqual(duringLockout.classification, .changed)
        XCTAssertEqual(duringLockout.reasons, [.usage])
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .slow)

        let afterLockout = policy.recordSuccess(
            quota(usage: 2),
            for: "provider",
            at: 901,
            quietWindow: quietWindow,
            canInvokeInference: true
        )
        XCTAssertEqual(afterLockout.classification, .unchanged)
    }

    func testLockoutDiscardsActivityHints() {
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

        XCTAssertEqual(
            policy.recordActivityHint(for: "provider", at: 700, quietWindow: quietWindow, canInvokeInference: true),
            .slow
        )
    }

    func testFailureDoesNotClearTheInferenceLockout() {
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

        _ = policy.recordFailure(for: "provider", at: 610, quietWindow: quietWindow)

        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .slow)
    }

    func testExtensionOverridesAnActiveInferenceLockout() {
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
        XCTAssertEqual(policy.cadence(for: "provider", at: 600, quietWindow: quietWindow), .slow)

        policy.recordExtension(for: "provider", duration: 900, at: 600)
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .fast)

        policy.stopExtension(for: "provider")
        XCTAssertEqual(policy.cadence(for: "provider", at: 700, quietWindow: quietWindow), .slow)
    }

    func testNonInferenceRefreshHasNoEpisodeCapOrLockout() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(usage: 0), for: "provider", at: 0, quietWindow: quietWindow)

        var usage = 0.0
        for step in stride(from: 0.0, through: 1200, by: 100) {
            usage += 1
            _ = policy.recordSuccess(quota(usage: usage), for: "provider", at: step, quietWindow: quietWindow)
        }

        XCTAssertEqual(policy.cadence(for: "provider", at: 1200, quietWindow: quietWindow), .fast)
    }
}
