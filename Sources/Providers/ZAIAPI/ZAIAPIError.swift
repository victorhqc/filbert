import Core
import Foundation

public enum ZAIAPIError: Error, Equatable, Sendable {
    case missingKey
    case http(Int)
    case rejected(code: Int)
    case network(Error)
    case decoding(Error)
    case internalInconsistency

    static let authenticationCodes: Set = [401, 1000, 1001, 1002]

    public static func == (lhs: ZAIAPIError, rhs: ZAIAPIError) -> Bool {
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

extension ZAIAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingKey:
            String(displayLocalized: "No API key configured.", bundle: .module)
        case .http(401):
            Self.authenticationFailed
        case let .rejected(code) where Self.authenticationCodes.contains(code):
            Self.authenticationFailed
        case .rejected:
            String(displayLocalized: "z.ai did not return a balance for this key.", bundle: .module)
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

    private static var authenticationFailed: String {
        String(
            displayLocalized: """
            Authentication failed. Check your API key. \
            Keys from \(ZAIAPIProvider.bigModelHost) need the base URL \
            \(ZAIAPIProvider.bigModelBaseURL.absoluteString).
            """,
            bundle: .module
        )
    }
}

extension ZAIAPIError: UnderlyingErrorProviding {
    public var underlyingError: (any Error)? {
        switch self {
        case let .network(error), let .decoding(error):
            error
        default:
            nil
        }
    }
}
