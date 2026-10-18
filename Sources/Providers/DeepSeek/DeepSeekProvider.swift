import Core
import Foundation

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
            String(displayLocalized: "No API key configured.", bundle: .module)
        case .http(401):
            String(displayLocalized: "Authentication failed. Check your API key.", bundle: .module)
        case let .http(code) where code == 429:
            String(displayLocalized: "Rate limited. Try again later.", bundle: .module)
        case .network:
            String(displayLocalized: "Network error. Check your connection.", bundle: .module)
        case .internalInconsistency:
            String(displayLocalized: "Internal error: unexpected auth shape.", bundle: .module)
        case .decoding, .http:
            String(displayLocalized: "Unexpected response from server.", bundle: .module)
        }
    }
}

extension DeepSeekError: UnderlyingErrorProviding {
    public var underlyingError: (any Error)? {
        switch self {
        case let .network(error), let .decoding(error):
            error
        default:
            nil
        }
    }
}

// MARK: - Wire types (private to this module)

struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

/// Wire shape is strings; the model wants numbers, so conversion happens in
/// the mapping step.
struct DeepSeekBalanceInfo: Decodable {
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

public enum DeepSeekPeakHours {
    public static let timeZone = TimeZone(identifier: "UTC")
    public static let windows = [
        PeakHoursWindow(startHour: 1, endHour: 4),
        PeakHoursWindow(startHour: 6, endHour: 10),
    ]
    public static let peakMultiplier = 2
    public static let offPeakMultiplier = 1
    public static let effectiveDate = Date(timeIntervalSince1970: 1_786_896_000)
}

// MARK: - Provider

public struct DeepSeekProvider: AIProvider {
    public static let providerId = "deepseek"
    public static let providerName = "DeepSeek"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static var providerDescription: String {
        String(displayLocalized: "Monitor prepaid balance", bundle: .module)
    }

    /// Host root for DeepSeek requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.deepseek.com")!
    /// `/user/balance` sends every amount with two decimals.
    static let balanceResolution = Decimal(sign: .plus, exponent: -2, significand: 1)
    public static let peakHoursConfig = PeakHoursConfig(
        timeZone: DeepSeekPeakHours.timeZone,
        windows: DeepSeekPeakHours.windows,
        peakMultiplier: DeepSeekPeakHours.peakMultiplier,
        offPeakMultiplier: DeepSeekPeakHours.offPeakMultiplier,
        effectiveDate: DeepSeekPeakHours.effectiveDate
    )

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
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw DeepSeekError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.network(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            throw DeepSeekError.http(httpResponse.statusCode)
        }

        let balanceResponse: DeepSeekBalanceResponse
        do {
            balanceResponse = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            throw DeepSeekError.decoding(error)
        }

        return map(balanceResponse, receivedAt: Date())
    }

    // MARK: - Mapping

    /// Always emits the balance lines so the user can see what's left even
    /// when the account is marked unavailable.
    func map(_ response: DeepSeekBalanceResponse, receivedAt: Date) -> ProviderQuota {
        let lines = response.balanceInfos.flatMap(balanceLines(for:))
        let headline = computeHeadline(response: response)

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline,
            lines: lines,
            lastUpdated: receivedAt,
            activityObservation: activityObservation(from: response, receivedAt: receivedAt),
            peakHoursConfig: Self.peakHoursConfig,
            headlineUsageLineId: response.balanceInfos.first.map { BalanceComponent.total.lineId(for: $0) }
        )
    }

    /// Only the total balance signals consumption. The granted and topped-up
    /// balances are component allocations: a grant, top-up, or expiry moves
    /// them without any inference usage, so they never count as activity.
    private func activityObservation(
        from response: DeepSeekBalanceResponse,
        receivedAt: Date
    ) -> ProviderActivityObservation {
        let totalIds = response.balanceInfos.map { BalanceComponent.total.lineId(for: $0) }
        let metrics = zip(response.balanceInfos, totalIds).compactMap { info, id in
            totalBalanceMetric(
                id: id,
                info: info,
                // Core rejects two descriptors for one line.
                isForecast: response.isAvailable && totalIds.filter { $0 == id }.count == 1,
                receivedAt: receivedAt
            )
        }
        // Every request reads the live balance. A charge reaches it about three minutes later.
        return ProviderActivityObservation(
            metrics: metrics,
            availability: response.isAvailable ? .available : .unavailable,
            freshness: .fresh
        )
    }

    private func totalBalanceMetric(
        id: String,
        info: DeepSeekBalanceInfo,
        isForecast: Bool,
        receivedAt: Date
    ) -> ProviderActivityMetric? {
        guard let value = Self.decimal(from: info.totalBalance) else {
            return nil
        }
        let descriptor = AllowanceForecastDescriptor(
            accounting: .balance,
            unit: .currency(info.currency),
            resolution: Self.balanceResolution,
            timing: .receipt(receivedAt),
            usageLineId: id
        )
        return ProviderActivityMetric(
            id: id,
            kind: .credits,
            value: .number(value),
            forecastDescriptor: isForecast ? descriptor : nil
        )
    }

    private enum BalanceComponent: CaseIterable {
        case total
        case granted
        case toppedUp

        var label: String {
            switch self {
            case .total: String(displayLocalized: "Total balance", bundle: .module)
            case .granted: String(displayLocalized: "Granted credits", bundle: .module)
            case .toppedUp: String(displayLocalized: "Topped up", bundle: .module)
            }
        }

        func rawAmount(in info: DeepSeekBalanceInfo) -> String {
            switch self {
            case .total: info.totalBalance
            case .granted: info.grantedBalance
            case .toppedUp: info.toppedUpBalance
            }
        }

        func lineId(for info: DeepSeekBalanceInfo) -> String {
            let component = switch self {
            case .total: "total-balance"
            case .granted: "granted-balance"
            case .toppedUp: "topped-up-balance"
            }
            return "\(component)-\(info.currency.lowercased())"
        }
    }

    /// Two equal amounts repeat each other, so only the total stays.
    private func balanceLines(for info: DeepSeekBalanceInfo) -> [UsageLine] {
        let amounts = BalanceComponent.allCases.compactMap { component in
            Self.decimal(from: component.rawAmount(in: info)).flatMap { amount in
                amount > 0 ? (component: component, amount: amount) : nil
            }
        }
        let hasEqualAmounts = Set(amounts.map(\.amount)).count < amounts.count
        let shown = hasEqualAmounts ? amounts.filter { $0.component == .total } : amounts

        return shown.map { component, amount in
            UsageLine(
                label: DisplayText { component.label },
                balance: UsageBalance(amount: .finite(amount), unit: .currency(info.currency)),
                id: component.lineId(for: info)
            )
        }
    }

    private func computeHeadline(response: DeepSeekBalanceResponse) -> DisplayText {
        if !response.isAvailable {
            return DisplayText { String(displayLocalized: "No balance available", bundle: .module) }
        }

        guard let info = response.balanceInfos.first,
              let total = Self.decimal(from: info.totalBalance)
        else {
            return DisplayText { String(displayLocalized: "No data", bundle: .module) }
        }

        let currency = info.currency
        return DisplayText {
            let amount = Self.currencyFormatter(currencyCode: currency)
                .string(from: NSDecimalNumber(decimal: total)) ?? "\(total)"
            return String(displayLocalized: "\(amount) left", bundle: .module)
        }
    }

    private static func decimal(from value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = DisplayLanguage.locale
        formatter.currencyCode = currencyCode
        return formatter
    }
}
