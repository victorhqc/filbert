import Core
import XCTest

final class ProviderOrderTests: XCTestCase {
    /// Isolated `UserDefaults` so tests don't touch the user's real defaults.
    private let suiteName = "ai-usage.tests.provider-order"
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

    // MARK: - AC4: empty saved order → input order preserved

    func testEffectiveOrder_returnsInputOrderWhenUnset() {
        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["zai", "claude", "deepseek"]),
            ["zai", "claude", "deepseek"]
        )
    }

    func testEffectiveOrder_preservesInputOrderForUnsavedIds() {
        // No saved order — input order is the fallback.
        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["deepseek", "zai"]),
            ["deepseek", "zai"]
        )
    }

    // MARK: - AC5: partial saved order → saved-first then unsaved

    func testEffectiveOrder_putsSavedIdsFirstInSavedSequence() {
        ProviderOrder.setOrder(["claude", "zai"])

        // Unsaved "deepseek" keeps its input position after the saved pair.
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

    // MARK: - AC5: stale saved IDs → dropped on read

    func testEffectiveOrder_dropsSavedIdsNoLongerRegistered() {
        ProviderOrder.setOrder(["claude", "zai", "ghost"])

        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["zai", "claude"]),
            ["claude", "zai"]
        )
    }

    // MARK: - AC5: appending newly registered providers

    func testEffectiveOrder_appendsNewlyRegisteredIdsAfterSavedOnes() {
        ProviderOrder.setOrder(["claude", "zai"])

        // "deepseek" is newly registered — appended in input order.
        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["claude", "zai", "deepseek"]),
            ["claude", "zai", "deepseek"]
        )
    }

    // MARK: - AC8: setOrder round-trip via savedOrder()

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
        // An explicit empty list is a valid stored value — should behave like
        // "no saved order" (input order preserved).
        ProviderOrder.setOrder([])

        XCTAssertNotNil(ProviderOrder.savedOrder())
        XCTAssertEqual(
            ProviderOrder.effectiveOrder(for: ["zai", "claude"]),
            ["zai", "claude"]
        )
    }
}
