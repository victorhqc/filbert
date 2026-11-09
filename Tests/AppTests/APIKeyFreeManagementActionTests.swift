@testable import App
import Core
import XCTest

final class APIKeyFreeManagementActionTests: XCTestCase {
    private let quota = ProviderQuota(
        providerId: "fixture",
        providerName: "Fixture",
        headline: DisplayText(verbatim: "10%"),
        lines: [],
        lastUpdated: Date()
    )

    func testALoadedProviderWithoutAHelperOffersNoRemoval() {
        let actions = APIKeyFreeManagementAction.actions(
            for: .loaded(quota),
            isEnabled: true,
            canInstall: false,
            canRemove: false,
            canImportCredentials: false
        )

        XCTAssertEqual(actions, [])
    }

    func testALoadedProviderWithAHelperOffersRemovalOnce() {
        let actions = APIKeyFreeManagementAction.actions(
            for: .loaded(quota),
            isEnabled: true,
            canInstall: false,
            canRemove: true,
            canImportCredentials: false
        )

        XCTAssertEqual(actions, [.removeHelper])
    }

    func testSetupOffersInstallAndImportWhenAvailable() {
        let state = ProviderState.setup(DisplayText(verbatim: "Install the helper"))

        let both = APIKeyFreeManagementAction.actions(
            for: state,
            isEnabled: true,
            canInstall: true,
            canRemove: true,
            canImportCredentials: true
        )
        let neither = APIKeyFreeManagementAction.actions(
            for: state,
            isEnabled: true,
            canInstall: false,
            canRemove: false,
            canImportCredentials: false
        )

        XCTAssertEqual(both, [.installHelper, .importCredentials])
        XCTAssertEqual(neither, [])
    }

    func testAnErrorOffersOnlyImport() {
        let actions = APIKeyFreeManagementAction.actions(
            for: .error(DisplayText(verbatim: "Failed")),
            isEnabled: true,
            canInstall: true,
            canRemove: true,
            canImportCredentials: true
        )

        XCTAssertEqual(actions, [.importCredentials])
    }

    func testADisabledProviderOffersNothing() {
        let actions = APIKeyFreeManagementAction.actions(
            for: .loaded(quota),
            isEnabled: false,
            canInstall: true,
            canRemove: true,
            canImportCredentials: true
        )

        XCTAssertEqual(actions, [])
    }
}
