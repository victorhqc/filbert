import Core
import XCTest

final class PanelLayoutPreferencesTests: XCTestCase {
    private let suiteName = "filbert.tests.panel-layout-preferences"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        PanelLayoutPreferences.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        PanelLayoutPreferences.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testLayout_isStackedWhenUnset() {
        XCTAssertEqual(PanelLayoutPreferences.layout, .stacked)
    }

    func testLayout_isStackedForUnknownStoredValue() {
        defaults.set("carousel", forKey: "panel-layout")

        XCTAssertEqual(PanelLayoutPreferences.layout, .stacked)
    }

    func testLayout_isStackedForNonStringStoredValue() {
        defaults.set(true, forKey: "panel-layout")

        XCTAssertEqual(PanelLayoutPreferences.layout, .stacked)
    }

    func testSetLayout_persistsAndReadsBack() {
        PanelLayoutPreferences.setLayout(.tabs)
        XCTAssertEqual(PanelLayoutPreferences.layout, .tabs)

        PanelLayoutPreferences.setLayout(.stacked)
        XCTAssertEqual(PanelLayoutPreferences.layout, .stacked)
    }

    func testSelectedTabProviderId_isNilWhenUnset() {
        XCTAssertNil(PanelLayoutPreferences.selectedTabProviderId)
    }

    func testSetSelectedTabProviderId_persistsAndReadsBack() {
        PanelLayoutPreferences.setSelectedTabProviderId("kimi-code")

        XCTAssertEqual(PanelLayoutPreferences.selectedTabProviderId, "kimi-code")
    }

    func testPreferences_surviveUserDefaultsSwap() throws {
        PanelLayoutPreferences.setLayout(.tabs)
        PanelLayoutPreferences.setSelectedTabProviderId("deepseek")

        let resurrected = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        PanelLayoutPreferences.setUserDefaults(resurrected)

        XCTAssertEqual(PanelLayoutPreferences.layout, .tabs)
        XCTAssertEqual(PanelLayoutPreferences.selectedTabProviderId, "deepseek")
    }
}
