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

    func testConnectivityErrorsAreFoundThroughWrappedCauses() {
        for code: URLError.Code in [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed,
        ] {
            XCTAssertTrue(isConnectivityError(URLError(code)))
            XCTAssertTrue(isConnectivityError(WrappingError(underlyingError: URLError(code))))
            XCTAssertTrue(isConnectivityError(
                WrappingError(underlyingError: WrappingError(underlyingError: URLError(code)))
            ))
        }
        XCTAssertFalse(isConnectivityError(URLError(.badServerResponse)))
        XCTAssertFalse(isConnectivityError(URLError(.secureConnectionFailed)))
        XCTAssertFalse(isConnectivityError(WrappingError(underlyingError: nil)))
        XCTAssertFalse(isConnectivityError(CancellationError()))
    }

    func testErrorChainStopsAtABoundedDepth() {
        let cycle = SelfWrappingError()
        XCTAssertEqual(errorChain(cycle).count, 8)
    }
}

private struct WrappingError: UnderlyingErrorProviding {
    let underlyingError: (any Error)?
}

private struct SelfWrappingError: UnderlyingErrorProviding {
    var underlyingError: (any Error)? {
        SelfWrappingError()
    }
}
