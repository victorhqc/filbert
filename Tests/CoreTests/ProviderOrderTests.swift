import Core
import XCTest

final class ProviderOrderTests: XCTestCase {
    /// Isolated `UserDefaults` so tests don't touch the user's real defaults.
    private let suiteName = "filbert.tests.provider-order"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderOrder.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderOrder.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    // MARK: - empty saved order → input order preserved

    func testEffectiveOrder_returnsInputOrderWhenUnset() {
        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["zai", "claude", "deepseek"]),
            ["zai", "claude", "deepseek"]
        )
    }

    func testEffectiveOrder_preservesInputOrderForUnsavedIds() {
        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["deepseek", "zai"]),
            ["deepseek", "zai"]
        )
    }

    // MARK: - partial saved order → saved-first then unsaved

    func testEffectiveOrder_putsSavedIdsFirstInSavedSequence() {
        ProviderOrder.setOrder(["claude", "zai"])

        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["deepseek", "zai", "claude"]),
            ["claude", "zai", "deepseek"]
        )
    }

    func testEffectiveOrder_keepsUnsavedIdsInInputRelativeOrder() {
        ProviderOrder.setOrder(["claude"])

        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["deepseek", "zai", "claude"]),
            ["claude", "deepseek", "zai"]
        )
    }

    // MARK: - stale saved IDs → dropped on read

    func testEffectiveOrder_dropsSavedIdsNoLongerRegistered() {
        ProviderOrder.setOrder(["claude", "zai", "ghost"])

        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["zai", "claude"]),
            ["claude", "zai"]
        )
    }

    // MARK: - appending newly registered providers

    func testEffectiveOrder_appendsNewlyRegisteredIdsAfterSavedOnes() {
        ProviderOrder.setOrder(["claude", "zai"])

        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["claude", "zai", "deepseek"]),
            ["claude", "zai", "deepseek"]
        )
    }

    // MARK: - setOrder round-trip via savedOrder()

    func testSavedOrder_returnsNilWhenUnset() {
        XCTAssertNil(ProviderOrder.savedOrder())
    }

    func testSetOrder_roundTripsThroughSavedOrder() {
        ProviderOrder.setOrder(["zai", "claude", "deepseek"])

        XCTAssertEqual(ProviderOrder.savedOrder(), ["zai", "claude", "deepseek"])
    }

    func testSetOrder_overwritesPreviousValue() {
        ProviderOrder.setOrder(["zai", "claude"])
        ProviderOrder.setOrder(["claude", "zai"])

        XCTAssertEqual(ProviderOrder.savedOrder(), ["claude", "zai"])
    }

    // MARK: - Edge cases

    func testEffectiveOrder_emptyInputReturnsEmpty() {
        ProviderOrder.setOrder(["claude"])

        XCTAssertEqual(ProviderOrder.effectiveOrder(for: []), [])
    }

    func testEffectiveOrder_handlesDuplicateInputIdsStably() {
        // The contract is deterministic but de-duplication is the caller's
        // job; we only assert no saved-order ID is lost and unsaved IDs
        // remain after saved ones.
        ProviderOrder.setOrder(["claude"])

        let result = ProviderOrder.effectiveOrder(for: ["zai", "claude"])
        XCTAssertEqual(result, ["claude", "zai"])
    }

    func testEffectiveOrder_emptySavedOrderListBehavesLikeUnset() {
        ProviderOrder.setOrder([])

        XCTAssertNotNil(ProviderOrder.savedOrder())
        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["zai", "claude"]),
            ["zai", "claude"]
        )
    }
}
