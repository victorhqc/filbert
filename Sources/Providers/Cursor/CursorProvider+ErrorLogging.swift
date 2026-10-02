import Core
import Foundation
import Security

extension CursorProvider {
    func recordCredentialFailure(operation: String, error: any Error) {
        guard !isCredentialCancellation(error) else { return }
        if let vaultError = error as? CursorCredentialVaultError {
            if case .unavailable = vaultError {
                return
            }
        }
        errorLog.record(
            component: "CursorProvider",
            operation: operation,
            code: "credential_read_failed",
            providerID: Self.providerId
        )
    }

    func isCredentialCancellation(_ error: any Error) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return true
        }
        if let keychainError = error as? KeychainError {
            return keychainError.isCancellation
        }
        if let vaultError = error as? CursorCredentialVaultError {
            if case let .keychain(keychainError) = vaultError {
                return keychainError.isCancellation
            }
        }
        if let externalError = error as? CursorExternalCredentialError {
            if case .keychain(errSecUserCanceled) = externalError {
                return true
            }
        }
        return false
    }
}
