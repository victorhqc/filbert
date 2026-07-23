import Core
import XCTest

final class ProviderCollapseStateTests: XCTestCase {
    private let suiteName = "filbert.tests.provider-collapse-state"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderCollapseState.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderCollapseState.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testCollapsedState_returnsNilWhenUntouched() {
        XCTAssertNil(ProviderCollapseState.collapsedState(for: "zai"))
    }

    func testSetCollapsed_roundTripsTrue() {
        ProviderCollapseState.setCollapsed(true, for: "zai")

        XCTAssertEqual(ProviderCollapseState.collapsedState(for: "zai"), true)
    }

    func testSetCollapsed_roundTripsFalse() {
        ProviderCollapseState.setCollapsed(false, for: "zai")

        XCTAssertEqual(ProviderCollapseState.collapsedState(for: "zai"), false)
    }

    func testStatesAreStoredIndependentlyByProviderId() {
        ProviderCollapseState.setCollapsed(true, for: "zai")
        ProviderCollapseState.setCollapsed(false, for: "deepseek")

        XCTAssertEqual(ProviderCollapseState.collapsedState(for: "zai"), true)
        XCTAssertEqual(ProviderCollapseState.collapsedState(for: "deepseek"), false)
    }
}
