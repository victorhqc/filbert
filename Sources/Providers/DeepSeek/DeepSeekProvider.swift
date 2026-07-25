import Core
import Foundation

// MARK: - Diagnostic logging

enum DeepSeekLog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[DeepSeekProvider] \(message())\n".utf8))
    }
}

// MARK: - Error

public enum DeepSeekError: Error, Equatable, Sendable {
    case missingKey
    case http(Int)
    case network(Error)
    case decoding(Error)
    case internalInconsistency

    public static func == (lhs: DeepSeekError, rhs: DeepSeekError) -> Bool {
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

extension DeepSeekError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingKey:
            String(localized: "No API key configured.")
        case .http(401):
            String(localized: "Authentication failed. Check your API key.")
        case let .http(code) where code == 429:
            String(localized: "Rate limited. Try again later.")
        case .network:
            String(localized: "Network error. Check your connection.")
        case .internalInconsistency:
            String(localized: "Internal error: unexpected auth shape.")
        case .decoding, .http:
            String(localized: "Unexpected response from server.")
        }
    }
}

// MARK: - Wire types (private to this module)

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

/// Wire shape is strings; the model wants numbers, so conversion happens in
/// the mapping step.
private struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

// MARK: - Provider

public struct DeepSeekProvider: AIProvider {
    public static let providerId = "deepseek"
    public static let providerName = "DeepSeek"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(localized: "Monitor prepaid balance")
    /// Host root for DeepSeek requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.deepseek.com")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchQuota(auth: ProviderAuth, baseURL: URL) async throws -> ProviderQuota {
        let apiKey: String
        switch auth {
        case let .apiKey(key):
            apiKey = key
        case .apiKeyFree:
            throw DeepSeekError.internalInconsistency
        }

        guard !apiKey.isEmpty else {
            throw DeepSeekError.missingKey
        }

        let endpoint = baseURL
            .appendingPathComponent("user")
            .appendingPathComponent("balance")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            DeepSeekLog.log("network error: \(error)")
            throw DeepSeekError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            DeepSeekLog.log("response was not HTTPURLResponse: \(response)")
            throw DeepSeekError.network(URLError(.badServerResponse))
        }

        let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        DeepSeekLog.log("status=\(httpResponse.statusCode) body=\(bodyPreview)")

        guard httpResponse.statusCode == 200 else {
            throw DeepSeekError.http(httpResponse.statusCode)
        }

        let balanceResponse: DeepSeekBalanceResponse
        do {
            balanceResponse = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            DeepSeekLog.log("decoding error: \(error)")
            throw DeepSeekError.decoding(error)
        }

        return map(balanceResponse)
    }

    // MARK: - Mapping

    /// Always emits the balance lines so the user can see what's left even
    /// when the account is marked unavailable.
    private func map(_ response: DeepSeekBalanceResponse) -> ProviderQuota {
        let lines = response.balanceInfos.flatMap { info -> [UsageLine] in
            // Currency formatting (symbol, decimals) is the UI's job, so
            // `used` is not derived here.
            let currency = info.currency
            return [
                UsageLine(
                    label: String(localized: "Total balance"),
                    used: nil,
                    total: Double(info.totalBalance),
                    unit: currency
                ),
                UsageLine(
                    label: String(localized: "Granted credits"),
                    used: nil,
                    total: Double(info.grantedBalance),
                    unit: currency
                ),
                UsageLine(
                    label: String(localized: "Topped up"),
                    used: nil,
                    total: Double(info.toppedUpBalance),
                    unit: currency
                ),
            ]
        }

        let headline = computeHeadline(response: response, lines: lines)

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline,
            lines: lines,
            lastUpdated: Date()
        )
    }

    private func computeHeadline(
        response: DeepSeekBalanceResponse,
        lines: [UsageLine]
    ) -> String {
        if !response.isAvailable {
            return String(localized: "No balance available")
        }

        let totalBalanceLabel = String(localized: "Total balance")
        guard let firstTotalLine = lines.first(where: { $0.label == totalBalanceLabel }),
              let total = firstTotalLine.total,
              let currency = firstTotalLine.unit
        else {
            return String(localized: "No data")
        }

        let amount = Self.currencyFormatter(currencyCode: currency).string(from: NSNumber(value: total)) ?? "\(total)"
        return String(localized: "\(amount) left")
    }

    private static func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter
    }
}
