import Core
import Foundation

public enum CursorError: Error, Equatable, Sendable {
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
        case .sessionExpired:
            String(displayLocalized: "Session expired", bundle: .module)
        case .clientIdRejected:
            String(displayLocalized: "Session expired — this provider needs an update", bundle: .module)
        case .http(401):
            String(displayLocalized: "Authentication failed", bundle: .module)
        case let .http(code) where code == 429:
            String(displayLocalized: "Rate limited", bundle: .module)
        case .network:
            String(displayLocalized: "Network error. Check your connection.", bundle: .module)
        case .decoding, .http:
            String(displayLocalized: "Unexpected response from server.", bundle: .module)
        }
    }
}

extension CursorError: UnderlyingErrorProviding {
    public var underlyingError: (any Error)? {
        switch self {
        case let .network(error), let .decoding(error):
            error
        default:
            nil
        }
    }
}
