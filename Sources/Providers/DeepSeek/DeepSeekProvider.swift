import Core
import Foundation

// MARK: - Diagnostic logging

/// Lightweight stderr logger so `swift run` surfaces what DeepSeek actually
/// returned. Diagnostic only.
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
    /// The registry routed `.apiKeyFree` auth to this provider, which is a
    /// contract-integrity violation — DeepSeek always expects an API key
    /// (core 03 AC3).
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

/// Top-level envelope for `GET /user/balance` (providers 04 AC2/AC3).
private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

/// One currency entry in the balance response. Wire shape is strings; the
/// model wants numbers, so conversion happens in the mapping step (providers
/// 04 AC2).
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
    public static let providerDescription = String(localized: "Monitor prepaid balance")
    /// Host root for DeepSeek requests; path segments live in `fetchQuota`
    /// (core 02 AC1/AC8).
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
            // The registry never routes .apiKeyFree to DeepSeek — this is a
            // contract-integrity assertion (core 03 AC3).
            throw DeepSeekError.internalInconsistency
        }

        guard !apiKey.isEmpty else {
            throw DeepSeekError.missingKey
        }

        // AC1: path is fixed; only the host comes from `baseURL` (core 02 AC8).
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

    /// Converts the decoded envelope into a `ProviderQuota`. Always emits the
    /// balance lines so the user can see what's left even when the account is
    /// marked unavailable (providers 04 AC3).
    private func map(_ response: DeepSeekBalanceResponse) -> ProviderQuota {
        let lines = response.balanceInfos.flatMap { info -> [UsageLine] in
            // AC2: total → `total`, granted/topped-up → their own lines, all
            // tagged with the raw currency code. Currency formatting (symbol,
            // decimals) is the UI's job, so `used` is not derived here.
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

    /// AC3 + AC4: when `is_available == false`, surface it explicitly; when
    /// true, format the first balance as `"<symbol><amount> left"`; fall back
    /// to the localized "No data" string when no balance parsed.
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

    /// Locale-aware currency formatter for the headline (providers 04 AC4).
    /// Local to this provider: per-AC2 currency formatting of the underlying
    /// values is still the UI's job; this only styles the headline amount.
    private static func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter
    }
}
