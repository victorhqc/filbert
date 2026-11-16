@testable import App
import Core
import XCTest

final class SettingsLayoutTests: XCTestCase {
    // MARK: - Duration menus

    func testASavedPresetKeepsThePresetList() {
        let presets: [TimeInterval] = [60, 300, 600]

        XCTAssertEqual(SettingsDurationOptions.options(presets: presets, including: 300), presets)
    }

    func testASavedValueOutsideThePresetsIsAddedInOrder() {
        let presets: [TimeInterval] = [60, 300, 600]

        XCTAssertEqual(SettingsDurationOptions.options(presets: presets, including: 420), [60, 300, 420, 600])
    }

    func testEveryPresetIsAValueTheScheduleSupports() {
        XCTAssertTrue(Set(SettingsDurationOptions.slowIntervalPresets)
            .isSubset(of: AutoRefreshPreferences.slowIntervalOptions))
        XCTAssertTrue(Set(SettingsDurationOptions.fastIntervalPresets)
            .isSubset(of: AutoRefreshPreferences.fastIntervalOptions))
        XCTAssertTrue(Set(SettingsDurationOptions.quietWindowPresets)
            .isSubset(of: AutoRefreshPreferences.quietWindowOptions))
    }

    func testTheDefaultsArePresets() {
        XCTAssertTrue(SettingsDurationOptions.slowIntervalPresets.contains(AutoRefreshPreferences.defaultSlowInterval))
        XCTAssertTrue(SettingsDurationOptions.fastIntervalPresets.contains(AutoRefreshPreferences.defaultFastInterval))
        XCTAssertTrue(SettingsDurationOptions.quietWindowPresets.contains(AutoRefreshPreferences.defaultQuietWindow))
    }

    // MARK: - Provider order

    func testMovingAVisibleProviderKeepsHiddenProvidersInTheirSlots() {
        let order = ProviderSettingsOrder.reordered(
            all: ["a", "hidden", "b", "c"],
            visible: ["a", "b", "c"],
            from: IndexSet(integer: 2),
            to: 0
        )

        XCTAssertEqual(order, ["c", "hidden", "a", "b"])
    }

    func testMovingDownPlacesTheProviderAfterItsNeighbor() {
        let order = ProviderSettingsOrder.reordered(
            all: ["a", "b", "c"],
            visible: ["a", "b", "c"],
            from: IndexSet(integer: 0),
            to: 2
        )

        XCTAssertEqual(order, ["b", "a", "c"])
    }

    // MARK: - Selected provider

    func testTheSelectedProviderStaysWhenItIsRegistered() {
        XCTAssertEqual(
            SettingsNavigation.resolvedProviderId(selected: "off", tracking: ["on"], all: ["on", "off"]),
            "off"
        )
    }

    func testAnUnknownSelectionFallsBackToTheFirstTrackedProvider() {
        XCTAssertEqual(
            SettingsNavigation.resolvedProviderId(selected: "gone", tracking: ["b"], all: ["a", "b"]),
            "b"
        )
        XCTAssertEqual(
            SettingsNavigation.resolvedProviderId(selected: nil, tracking: [], all: ["a", "b"]),
            "a"
        )
        XCTAssertNil(SettingsNavigation.resolvedProviderId(selected: nil, tracking: [], all: []))
    }

    // MARK: - Status words

    func testEveryProviderUsesTheSameStatusWords() {
        let quota = ProviderQuota(
            providerId: "fixture",
            providerName: "Fixture",
            headline: DisplayText(verbatim: "10%"),
            lines: [],
            lastUpdated: Date()
        )

        XCTAssertEqual(ProviderStatusPresentation(state: .loaded(quota), isEnabled: true), .ready)
        XCTAssertEqual(ProviderStatusPresentation(state: .unconfigured, isEnabled: true), .needsSetup)
        XCTAssertEqual(
            ProviderStatusPresentation(state: .setup(DisplayText(verbatim: "Install")), isEnabled: true),
            .needsSetup
        )
        XCTAssertEqual(ProviderStatusPresentation(state: nil, isEnabled: true), .needsSetup)
        XCTAssertEqual(
            ProviderStatusPresentation(state: .error(DisplayText(verbatim: "Failed")), isEnabled: true),
            .error
        )
        XCTAssertEqual(ProviderStatusPresentation(state: .loading, isEnabled: true), .working)
        XCTAssertEqual(ProviderStatusPresentation(state: .loaded(quota), isEnabled: false), .off)
    }
}
