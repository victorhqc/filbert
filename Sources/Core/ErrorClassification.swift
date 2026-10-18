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

public func isConnectivityError(_ error: any Error) -> Bool {
    let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .timedOut,
        .internationalRoamingOff,
        .dataNotAllowed,
    ]
    return errorChain(error).contains { link in
        (link as? URLError).map { connectivityCodes.contains($0.code) } ?? false
    }
}
