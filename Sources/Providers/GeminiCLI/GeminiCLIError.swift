import Core
import Foundation

public enum GeminiCLIError: Error, Equatable, Sendable {
    case internalInconsistency
    case missingCredentials
    case invalidCredentials
    case keychainAccessDenied
    case signedOut
    case projectSetupRequired
    case rateLimited
    case http(Int)
    case network(URLError.Code?)
    case timeout
    case decoding
    case payloadDrift
}

extension GeminiCLIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .internalInconsistency:
            String(displayLocalized: "Internal error: unexpected credential type.", bundle: .module)
        case .missingCredentials:
            String(displayLocalized: "Sign in to Gemini CLI so Filbert can check its usage.", bundle: .module)
        case .invalidCredentials:
            String(
                displayLocalized: "Gemini CLI credentials are unsupported. Update Gemini CLI and sign in again.",
                bundle: .module
            )
        case .keychainAccessDenied:
            String(
                displayLocalized: "Filbert could not read the Gemini CLI Keychain item. Allow access and try again.",
                bundle: .module
            )
        case .signedOut:
            String(
                displayLocalized: "Gemini CLI is signed out. Open Gemini CLI and sign in with Google.",
                bundle: .module
            )
        case .projectSetupRequired:
            String(
                displayLocalized: "Complete Gemini CLI setup or configure a Google Cloud project, then try again.",
                bundle: .module
            )
        case .rateLimited:
            String(displayLocalized: "Gemini CLI is rate limited. Try again later.", bundle: .module)
        case let .http(status) where status == 401:
            String(displayLocalized: "Gemini CLI authentication failed. Sign in again.", bundle: .module)
        case let .http(status) where status == 403:
            String(displayLocalized: "Gemini CLI account or project setup is required.", bundle: .module)
        case .http:
            String(
                displayLocalized: "Gemini CLI usage service returned an unexpected error. Try again later.",
                bundle: .module
            )
        case .network:
            String(
                displayLocalized: "Could not reach Gemini CLI usage service. Check your connection and try again.",
                bundle: .module
            )
        case .timeout:
            String(displayLocalized: "Gemini CLI usage request timed out. Try again later.", bundle: .module)
        case .decoding:
            String(
                displayLocalized: "Gemini CLI returned data Filbert could not read. Update Filbert and try again.",
                bundle: .module
            )
        case .payloadDrift:
            String(displayLocalized: "Gemini CLI returned an unexpected usage response.", bundle: .module)
        }
    }
}

extension GeminiCLIError: UnderlyingErrorProviding {
    public var underlyingError: (any Error)? {
        guard case let .network(code?) = self else { return nil }
        return URLError(code)
    }
}
