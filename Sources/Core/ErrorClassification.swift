import Foundation

public func isCancellationError(_ error: any Error) -> Bool {
    error is CancellationError
        || (error as? URLError)?.code == .cancelled
        || (error as? KeychainError)?.isCancellation == true
}

public func isMissingCredentialError(_ error: any Error) -> Bool {
    error as? ProviderSetupError == .missingCredentials
        || (error as? KeychainError)?.isMissingCredential == true
}
