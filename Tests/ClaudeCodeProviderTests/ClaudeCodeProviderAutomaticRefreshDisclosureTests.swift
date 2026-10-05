@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeRefreshDisclosureTests: XCTestCase {
    func testProviderDisclosesAutomaticRefreshQuotaUse() throws {
        let disclosure = try XCTUnwrap(ClaudeCodeProvider.automaticRefreshDisclosure)

        XCTAssertEqual(disclosure.command, "claude -p \"/usage\"")
        XCTAssertEqual(disclosure.quotaName, "Claude Code")
    }

    func testProviderDeclaresPossibleConsumptionAndInferenceCapability() {
        XCTAssertEqual(
            ClaudeCodeProvider.refreshCharacteristics,
            ProviderRefreshCharacteristics(
                costEvidence: .possibleConsumption,
                canInvokeInference: true
            )
        )
    }
}
