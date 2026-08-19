@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class MenuBarProviderSelectionViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.menu-bar-provider-selection-view-model"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        MenuBarProviderSelectionPreferences.setUserDefaults(defaults)
        VintageMacIcon.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        MenuBarProviderSelectionPreferences.setUserDefaults(.standard)
        VintageMacIcon.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testChangingSelectionModeUpdatesTheViewModelAndPersistedPreference() {
        let viewModel = QuotaViewModel(registry: ProviderRegistry())
        viewModel.configuredProviderIds = ["first", "newer"]
        viewModel.enabledProviderIds = ["first", "newer"]
        viewModel.providerStates = [
            "first": loadedState(for: "first", updatedAt: 1),
            "newer": loadedState(for: "newer", updatedAt: 2),
        ]

        XCTAssertTrue(viewModel.isAutomaticMenuBarProviderSelection)
        XCTAssertEqual(viewModel.menuBarProviderId, "newer")

        viewModel.setAutomaticMenuBarProviderSelection(false)

        XCTAssertFalse(viewModel.isAutomaticMenuBarProviderSelection)
        XCTAssertFalse(MenuBarProviderSelectionPreferences.isAutomatic)
        XCTAssertEqual(viewModel.menuBarProviderId, "first")
    }

    func testChangingVintageMacSettingUpdatesTheViewModelAndPersistedPreference() {
        let viewModel = QuotaViewModel(registry: ProviderRegistry())

        XCTAssertFalse(viewModel.isVintageMacIconEnabled)

        viewModel.setVintageMacIconEnabled(true)

        XCTAssertTrue(viewModel.isVintageMacIconEnabled)
        XCTAssertTrue(VintageMacIcon.isEnabled)
    }

    private func loadedState(for providerId: String, updatedAt: TimeInterval) -> ProviderState {
        .loaded(
            ProviderQuota(
                providerId: providerId,
                providerName: providerId,
                headline: "",
                lines: [UsageLine(label: "Window", percentage: 20)],
                lastUpdated: Date(timeIntervalSinceReferenceDate: updatedAt)
            )
        )
    }
}
