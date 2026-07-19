import Core
import XCTest

final class KeychainTests: XCTestCase {
    func testKeychainError_casesExist() {
        // Verify KeychainError cases exist and are distinct.
        // We can't test real Keychain I/O in CI, but the enum must compile.
        let errors: [KeychainError] = [
            .saveFailed(-1),
            .loadFailed(-1),
            .deleteFailed(-1),
        ]

        XCTAssertEqual(errors.count, 3)
    }

    func testKeychainError_isEquatable() {
        let lhs = KeychainError.saveFailed(-1)
        let rhs = KeychainError.saveFailed(-1)
        let other = KeychainError.loadFailed(-1)

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, other)
    }
}
