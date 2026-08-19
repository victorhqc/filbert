@testable import Core
import Foundation
import XCTest

final class MenuBarProviderSelectionPreferencesTests: XCTestCase {
    private let suiteName = "filbert.tests.menu-bar-provider-selection-preferences"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        MenuBarProviderSelectionPreferences.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        MenuBarProviderSelectionPreferences.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testMissingValueDefaultsToAutomaticSelection() {
        XCTAssertTrue(MenuBarProviderSelectionPreferences.isAutomatic)
    }

    func testAutomaticSelectionRoundTripsBothValues() {
        MenuBarProviderSelectionPreferences.isAutomatic = false
        XCTAssertFalse(MenuBarProviderSelectionPreferences.isAutomatic)

        MenuBarProviderSelectionPreferences.isAutomatic = true
        XCTAssertTrue(MenuBarProviderSelectionPreferences.isAutomatic)
    }
}
