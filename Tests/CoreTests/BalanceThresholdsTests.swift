import Core
import XCTest

final class BalanceThresholdsTests: XCTestCase {
    /// Isolated `UserDefaults` so tests don't touch the user's real defaults.
    private let suiteName = "filbert.tests.balance-thresholds"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        BalanceThresholds.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        BalanceThresholds.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    // MARK: - AC2: defaults when unset

    func testLow_returnsDefaultWhenUnset() {
        XCTAssertEqual(BalanceThresholds.low, 5)
    }

    func testOk_returnsDefaultWhenUnset() {
        XCTAssertEqual(BalanceThresholds.ok, 20)
    }

    // MARK: - AC2: round-trip

    func testSet_persistsAndReadsBack() {
        BalanceThresholds.set(low: 10, ok: 50)

        XCTAssertEqual(BalanceThresholds.low, 10)
        XCTAssertEqual(BalanceThresholds.ok, 50)
    }

    // MARK: - AC2: clamps ok upward so ok > low always holds

    func testSet_clampsOkUpwardWhenEqualToLow() {
        BalanceThresholds.set(low: 10, ok: 10)

        XCTAssertEqual(BalanceThresholds.low, 10)
        XCTAssertEqual(BalanceThresholds.ok, 11)
    }

    func testSet_clampsOkUpwardWhenBelowLow() {
        BalanceThresholds.set(low: 20, ok: 5)

        XCTAssertEqual(BalanceThresholds.low, 20)
        XCTAssertEqual(BalanceThresholds.ok, 21)
    }

    // MARK: - AC2: rejects negative low by ignoring the write

    func testSet_rejectsNegativeLow() {
        BalanceThresholds.set(low: -5, ok: 20)

        // Nothing persisted — defaults remain.
        XCTAssertEqual(BalanceThresholds.low, 5)
        XCTAssertEqual(BalanceThresholds.ok, 20)
    }

    func testSet_acceptsZeroLow() {
        BalanceThresholds.set(low: 0, ok: 10)

        XCTAssertEqual(BalanceThresholds.low, 0)
        XCTAssertEqual(BalanceThresholds.ok, 10)
    }

    // MARK: - AC2: survives relaunch (new instance over the same suite)

    func testSet_survivesRelaunch() throws {
        BalanceThresholds.set(low: 7, ok: 42)

        // Simulate relaunch by creating a fresh instance over the same suite.
        let resurrected = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        BalanceThresholds.setUserDefaults(resurrected)

        XCTAssertEqual(BalanceThresholds.low, 7)
        XCTAssertEqual(BalanceThresholds.ok, 42)
    }
}
