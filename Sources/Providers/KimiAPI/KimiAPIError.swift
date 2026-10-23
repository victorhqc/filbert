import Core
import Foundation

public enum KimiAPIError: Error, Equatable, Sendable {
    case missingKey
    case http(Int)
    case rejected(code: Int)
    case network(Error)
    case decoding(Error)
    case internalInconsistency

    public static func == (lhs: KimiAPIError, rhs: KimiAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.missingKey, .missingKey): true
        case (.internalInconsistency, .internalInconsistency): true
        case let (.http(lhsVal), .http(rhsVal)): lhsVal == rhsVal
        case let (.rejected(lhsVal), .rejected(rhsVal)): lhsVal == rhsVal
        case let (.network(lhsVal), .network(rhsVal)): lhsVal.localizedDescription == rhsVal.localizedDescription
        case let (.decoding(lhsVal), .decoding(rhsVal)): lhsVal.localizedDescription == rhsVal.localizedDescription
        default: false
        }
    }
}

extension KimiAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingKey:
            String(displayLocalized: "No API key configured.", bundle: .module)
        case .http(401):
            // A key from the other region's platform gets the same 401 as an invalid key.
            String(
                displayLocalized: """
                Authentication failed. Check your API key. \
                Keys from \(KimiAPIProvider.chinaConsoleHost) need the base URL \
                \(KimiAPIProvider.chinaBaseURL.absoluteString).
                """,
                bundle: .module
            )
        case .http(429):
            String(displayLocalized: "Rate limited. Try again later.", bundle: .module)
        case .network:
            String(displayLocalized: "Network error. Check your connection.", bundle: .module)
        case .internalInconsistency:
            String(displayLocalized: "Internal error: unexpected credential type.", bundle: .module)
        case .decoding, .http, .rejected:
            String(displayLocalized: "Unexpected response from server.", bundle: .module)
        }
    }
}

extension KimiAPIError: UnderlyingErrorProviding {
    public var underlyingError: (any Error)? {
        switch self {
        case let .network(error), let .decoding(error):
            error
        default:
            nil
        }
    }
}
