@testable import Core
import Foundation
import XCTest

final class AutoRefreshPreferencesTests: XCTestCase {
    private let suiteName = "filbert.tests.auto-refresh-preferences"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        AutoRefreshPreferences.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        AutoRefreshPreferences.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testMissingValuesUseDocumentedDefaults() {
        XCTAssertFalse(AutoRefreshPreferences.isEnabled(for: "provider"))
        XCTAssertEqual(AutoRefreshPreferences.mode, .regular)
        XCTAssertEqual(AutoRefreshPreferences.slowInterval, 5 * 60)
        XCTAssertEqual(AutoRefreshPreferences.fastInterval, 30)
    }

    func testProviderOptInPersistsIndependently() {
        AutoRefreshPreferences.setEnabled(true, for: "first")

        XCTAssertTrue(AutoRefreshPreferences.isEnabled(for: "first"))
        XCTAssertFalse(AutoRefreshPreferences.isEnabled(for: "second"))

        AutoRefreshPreferences.setEnabled(true, for: "second")
        AutoRefreshPreferences.setEnabled(false, for: "first")

        XCTAssertFalse(AutoRefreshPreferences.isEnabled(for: "first"))
        XCTAssertTrue(AutoRefreshPreferences.isEnabled(for: "second"))
    }

    func testSharedValuesPersistWhenSupported() {
        AutoRefreshPreferences.mode = .smart
        AutoRefreshPreferences.slowInterval = 15 * 60
        AutoRefreshPreferences.fastInterval = 45

        XCTAssertEqual(AutoRefreshPreferences.mode, .smart)
        XCTAssertEqual(AutoRefreshPreferences.slowInterval, 15 * 60)
        XCTAssertEqual(AutoRefreshPreferences.fastInterval, 45)
    }

    func testInvalidStoredValuesResolveToDefaults() {
        defaults.set("unknown", forKey: "automatic-refresh-mode")
        defaults.set(7, forKey: "automatic-refresh-slow-interval")
        defaults.set(90, forKey: "automatic-refresh-fast-interval")

        XCTAssertEqual(AutoRefreshPreferences.mode, .regular)
        XCTAssertEqual(AutoRefreshPreferences.slowInterval, 5 * 60)
        XCTAssertEqual(AutoRefreshPreferences.fastInterval, 30)
    }
}
