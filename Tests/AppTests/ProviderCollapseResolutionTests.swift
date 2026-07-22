@testable import App
import XCTest

@MainActor
final class ProviderCollapseResolutionTests: XCTestCase {
    func testTopProviderDefaultsToExpanded() {
        XCTAssertFalse(
            QuotaViewModel.resolvedCollapseState(
                providerId: "zai",
                topProviderId: "zai",
                savedState: nil
            )
        )
    }

    func testProviderBelowTopDefaultsToCollapsed() {
        XCTAssertTrue(
            QuotaViewModel.resolvedCollapseState(
                providerId: "deepseek",
                topProviderId: "zai",
                savedState: nil
            )
        )
    }

    func testSavedCollapsedStateOverridesTopPosition() {
        XCTAssertTrue(
            QuotaViewModel.resolvedCollapseState(
                providerId: "zai",
                topProviderId: "zai",
                savedState: true
            )
        )
    }

    func testSavedExpandedStateOverridesLowerPosition() {
        XCTAssertFalse(
            QuotaViewModel.resolvedCollapseState(
                providerId: "deepseek",
                topProviderId: "zai",
                savedState: false
            )
        )
    }
}
