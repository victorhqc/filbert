import Core
import Foundation

public enum KimiCodeError: Error, Equatable, Sendable {
    case missingKey
    case http(Int)
    case network(Error)
    case decoding(Error)
    case internalInconsistency

    public static func == (lhs: KimiCodeError, rhs: KimiCodeError) -> Bool {
        switch (lhs, rhs) {
        case (.missingKey, .missingKey): true
        case (.internalInconsistency, .internalInconsistency): true
        case let (.http(lhsVal), .http(rhsVal)): lhsVal == rhsVal
        case let (.network(lhsVal), .network(rhsVal)): lhsVal.localizedDescription == rhsVal.localizedDescription
        case let (.decoding(lhsVal), .decoding(rhsVal)): lhsVal.localizedDescription == rhsVal.localizedDescription
        default: false
        }
    }
}

extension KimiCodeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingKey:
            String(displayLocalized: "No API key configured.", bundle: .module)
        case .http(401):
            // A key from the other region gets the same 401 as an invalid key.
            String(
                displayLocalized: """
                Authentication failed. Check your Kimi Code API key. \
                Accounts in mainland China need the base URL \
                \(KimiCodeProvider.chinaBaseURL.absoluteString).
                """,
                bundle: .module
            )
        case .http(403):
            String(displayLocalized: "No Kimi Code access. Check your Kimi membership.", bundle: .module)
        case .http(429):
            String(displayLocalized: "Rate limited. Try again later.", bundle: .module)
        case .network:
            String(displayLocalized: "Network error. Check your connection.", bundle: .module)
        case .internalInconsistency:
            String(displayLocalized: "Internal error: unexpected credential type.", bundle: .module)
        case .decoding, .http:
            String(displayLocalized: "Unexpected response from server.", bundle: .module)
        }
    }
}

extension KimiCodeError: UnderlyingErrorProviding {
    public var underlyingError: (any Error)? {
        switch self {
        case let .network(error), let .decoding(error):
            error
        default:
            nil
        }
    }
}
