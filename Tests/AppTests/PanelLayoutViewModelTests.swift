@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class PanelLayoutViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.panel-layout-view-model"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        PanelLayoutPreferences.setUserDefaults(defaults)
        ProviderCollapseState.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        PanelLayoutPreferences.setUserDefaults(.standard)
        ProviderCollapseState.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testResolvedSelectedTab_keepsTheSavedProviderWhenConfigured() {
        XCTAssertEqual(
            QuotaViewModel.resolvedSelectedTab(saved: "second", configured: ["first", "second"]),
            "second"
        )
    }

    func testResolvedSelectedTab_fallsBackToTheFirstProviderWhenNothingIsSaved() {
        XCTAssertEqual(
            QuotaViewModel.resolvedSelectedTab(saved: nil, configured: ["first", "second"]),
            "first"
        )
    }

    func testResolvedSelectedTab_fallsBackToTheFirstProviderWhenTheSavedOneIsGone() {
        XCTAssertEqual(
            QuotaViewModel.resolvedSelectedTab(saved: "removed", configured: ["first", "second"]),
            "first"
        )
    }

    func testResolvedSelectedTab_isNilWithoutConfiguredProviders() {
        XCTAssertNil(QuotaViewModel.resolvedSelectedTab(saved: "removed", configured: []))
    }

    func testDefaultLayoutIsStacked() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.panelLayout, .stacked)
    }

    func testChangingLayoutUpdatesTheViewModelAndPersistedPreference() {
        let viewModel = makeViewModel()

        viewModel.setPanelLayout(.tabs)

        XCTAssertEqual(viewModel.panelLayout, .tabs)
        XCTAssertEqual(PanelLayoutPreferences.layout, .tabs)
    }

    func testSelectingATabPersistsIt() {
        let viewModel = makeViewModel()
        viewModel.configuredProviderIds = ["first", "second"]

        viewModel.selectTab("second")

        XCTAssertEqual(viewModel.selectedTabProviderId, "second")
        XCTAssertEqual(PanelLayoutPreferences.selectedTabProviderId, "second")
    }

    func testFallbackDoesNotOverwriteTheSavedTab() {
        PanelLayoutPreferences.setSelectedTabProviderId("returning")
        let viewModel = makeViewModel()
        viewModel.configuredProviderIds = ["first"]

        XCTAssertEqual(viewModel.selectedTabProviderId, "first")
        XCTAssertEqual(PanelLayoutPreferences.selectedTabProviderId, "returning")

        viewModel.configuredProviderIds = ["first", "returning"]

        XCTAssertEqual(viewModel.selectedTabProviderId, "returning")
    }

    func testChangingLayoutKeepsCollapseStates() {
        ProviderCollapseState.setCollapsed(false, for: "second")
        ProviderCollapseState.setCollapsed(true, for: "first")
        let viewModel = makeViewModel()
        viewModel.configuredProviderIds = ["first", "second"]

        viewModel.setPanelLayout(.tabs)
        viewModel.selectTab("second")
        viewModel.setPanelLayout(.stacked)

        XCTAssertTrue(viewModel.isCollapsed("first"))
        XCTAssertFalse(viewModel.isCollapsed("second"))
    }

    func testTogglingCollapseKeepsTheSavedTab() {
        let viewModel = makeViewModel()
        viewModel.configuredProviderIds = ["first", "second"]
        viewModel.selectTab("second")

        viewModel.toggleCollapsed("first")

        XCTAssertEqual(PanelLayoutPreferences.selectedTabProviderId, "second")
    }

    private func makeViewModel() -> QuotaViewModel {
        QuotaViewModel(registry: ProviderRegistry(), errorLog: AppTestErrorLog.make())
    }
}
