import Foundation

public enum CursorError: Error, Equatable, Sendable {
    case missingToken
    /// The session is no longer valid — the refresh returned `shouldLogout`
    /// or an empty access token.
    case sessionExpired
    // Cursor rotated its first-party `client_id`; filbert needs an update.
    case clientIdRejected
    case http(Int)
    case network(Error)
    case decoding(Error)

    public static func == (lhs: CursorError, rhs: CursorError) -> Bool {
        switch (lhs, rhs) {
        case (.missingToken, .missingToken): true
        case (.sessionExpired, .sessionExpired): true
        case (.clientIdRejected, .clientIdRejected): true
        case let (.http(lhsVal), .http(rhsVal)): lhsVal == rhsVal
        case let (.network(lhsVal), .network(rhsVal)):
            lhsVal.localizedDescription == rhsVal.localizedDescription
        case let (.decoding(lhsVal), .decoding(rhsVal)):
            lhsVal.localizedDescription == rhsVal.localizedDescription
        default: false
        }
    }
}

extension CursorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingToken:
            String(
                localized: "Cursor CLI not installed — run `agent login`, or sign in to the Cursor app."
            )
        case .sessionExpired:
            String(localized: "Session expired")
        case .clientIdRejected:
            String(localized: "Session expired — this provider needs an update")
        case .http(401):
            String(localized: "Authentication failed")
        case let .http(code) where code == 429:
            String(localized: "Rate limited")
        case .network:
            String(localized: "Network error. Check your connection.")
        case .decoding, .http:
            String(localized: "Unexpected response from server.")
        }
    }
}
