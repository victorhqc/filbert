import Core
import Foundation
import Security
import XCTest

final class ErrorClassificationTests: XCTestCase {
    func testIntentionalCancellationsHaveOneClassification() {
        let errors: [any Error] = [
            CancellationError(),
            URLError(.cancelled),
            KeychainError.loadFailed(errSecUserCanceled),
            KeychainError.saveFailed(errSecUserCanceled),
            KeychainError.deleteFailed(errSecUserCanceled),
        ]
        for error in errors {
            XCTAssertTrue(isCancellationError(error))
        }
        XCTAssertFalse(isCancellationError(URLError(.timedOut)))
        XCTAssertFalse(isCancellationError(KeychainError.loadFailed(errSecAuthFailed)))
    }

    func testCredentialAbsenceDoesNotIncludeAccessFailures() {
        XCTAssertTrue(isMissingCredentialError(KeychainError.loadFailed(errSecItemNotFound)))
        XCTAssertTrue(isMissingCredentialError(ProviderSetupError.missingCredentials))
        XCTAssertFalse(isMissingCredentialError(KeychainError.loadFailed(errSecAuthFailed)))
        XCTAssertFalse(isMissingCredentialError(KeychainError.saveFailed(errSecItemNotFound)))
        XCTAssertFalse(isMissingCredentialError(ProviderSetupError.notSupported))
    }
}
