import Core
import Foundation

// MARK: - Diagnostic logging

/// Lightweight stderr logger so `swift run` surfaces what z.ai actually
/// returned. Diagnostic only — remove or gate behind a flag once the wire
/// format is confirmed stable.
enum ZAILog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[ZAIProvider] \(message())\n".utf8))
    }
}

// MARK: - Error

public enum ZAIError: Error, Equatable, Sendable {
    case missingKey
    case http(Int)
    case network(Error)
    case decoding(Error)
    /// The registry routed `.apiKeyFree` auth to this provider, which is a
    /// contract-integrity violation — z.ai always expects an API key (core 03 AC3).
    case internalInconsistency

    public static func == (lhs: ZAIError, rhs: ZAIError) -> Bool {
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

extension ZAIError: LocalizedError {
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

private struct ZAIQuotaResponse: Decodable {
    let data: ZAIData
}

private struct ZAIData: Decodable {
    let limits: [ZAILimit]
}

private struct ZAILimit: Decodable {
    let type: String
    let unit: Int
    let percentage: Double?
    let usage: Double?
    let currentValue: Double?
    let remaining: Double?
    let nextResetTime: Int64?
    let usageDetails: [ZAIUsageDetail]?
}

private struct ZAIUsageDetail: Decodable {
    let modelCode: String
    let usage: Double?
}

// MARK: - Label lookup

private struct ZAILimitLabel {
    let type: String
    let unit: Int
    let label: String

    /// Recognized (type, unit) pairs (providers 01 AC2).
    /// Unknown pairs are silently ignored during mapping.
    static let known: [ZAILimitLabel] = [
        ZAILimitLabel(type: "TOKENS_LIMIT", unit: 3, label: "5-hour window"),
        ZAILimitLabel(type: "TOKENS_LIMIT", unit: 6, label: "Weekly"),
        ZAILimitLabel(type: "TIME_LIMIT", unit: 5, label: "Monthly web-tool calls"),
    ]

    static func lookup(type: String, unit: Int) -> String? {
        known.first { $0.type == type && $0.unit == unit }?.label
    }
}

// MARK: - Peak-hours metadata (ui 04 AC3/AC4)

/// GLM Coding Plan peak-hours rules sourced from zai-bar's README.
/// Last verified: 2026-07-21.
///
/// These are provider-level constants — the view layer reads them so
/// pricing rules aren't buried in UI-only code. When z.ai announces
/// a change (extended promo, new multiplier, different peak window),
/// updating this single location is sufficient.
public enum ZAIPeakHours {
    /// China Standard Time (UTC+8, no DST).
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai")

    /// Peak window: 14:00–18:00 in Asia/Shanghai.
    public static let peakStartHour = 14
    public static let peakEndHour = 18

    /// Advanced-model (GLM-5.2 / GLM-5-Turbo) multiplier during peak hours.
    public static let peakMultiplier = 3

    /// Off-peak multiplier after the limited-time promo ends.
    public static let offPeakMultiplier = 2

    /// Off-peak multiplier while the limited-time promo is active.
    public static let promoMultiplier = 1

    /// Limited-time promo cutoff: 2026-10-01 00:00 Asia/Shanghai.
    /// After this date the off-peak multiplier flips from
    /// `promoMultiplier` to `offPeakMultiplier`.
    public static let promoEndDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.timeZone = timeZone
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantFuture
    }()
}

// MARK: - Provider

public struct ZAIProvider: AIProvider {
    public static let providerId = "zai"
    public static let providerName = "z.ai"
    public static let providerDescription = String(localized: "Monitor API usage and quotas")
    /// Host root for z.ai requests; path segments live in `fetchQuota` (core 02 AC1/AC8).
    public static let baseURL = URL(string: "https://api.z.ai")!

    /// Provider-agnostic config the view layer reads for the peak-hours block.
    /// Sourced from `ZAIPeakHours` (zai-bar README).
    public static let peakHoursConfig = PeakHoursConfig(
        timeZone: ZAIPeakHours.timeZone,
        peakStartHour: ZAIPeakHours.peakStartHour,
        peakEndHour: ZAIPeakHours.peakEndHour,
        peakMultiplier: ZAIPeakHours.peakMultiplier,
        offPeakMultiplier: ZAIPeakHours.offPeakMultiplier,
        promoMultiplier: ZAIPeakHours.promoMultiplier,
        promoEndDate: ZAIPeakHours.promoEndDate
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
            // The registry never routes .apiKeyFree to ZAI — this is a
            // contract-integrity assertion (core 03 AC3).
            throw ZAIError.internalInconsistency
        }

        guard !apiKey.isEmpty else {
            throw ZAIError.missingKey
        }

        // Path is plan-agnostic; only the host comes from `baseURL` (core 02 AC8).
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("monitor")
            .appendingPathComponent("usage")
            .appendingPathComponent("quota")
            .appendingPathComponent("limit")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        // z.ai's monitor endpoint expects the raw token, NOT an "Authorization: Bearer …"
        // scheme. Sending a "Bearer " prefix is rejected as unauthenticated. This holds
        // for both regular API and Coding Plan keys — the endpoint is plan-agnostic.
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            ZAILog.log("network error: \(error)")
            throw ZAIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            ZAILog.log("response was not HTTPURLResponse: \(response)")
            throw ZAIError.network(URLError(.badServerResponse))
        }

        let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        ZAILog.log("status=\(httpResponse.statusCode) body=\(bodyPreview)")

        guard httpResponse.statusCode == 200 else {
            throw ZAIError.http(httpResponse.statusCode)
        }

        let quotaResponse: ZAIQuotaResponse
        do {
            quotaResponse = try JSONDecoder().decode(ZAIQuotaResponse.self, from: data)
        } catch {
            ZAILog.log("decoding error: \(error)")
            throw ZAIError.decoding(error)
        }

        return map(quotaResponse)
    }

    // MARK: - Mapping

    private func map(_ response: ZAIQuotaResponse) -> ProviderQuota {
        let limits = response.data.limits
        var lines: [UsageLine] = []
        var fiveHourLimit: ZAILimit?
        var weeklyLimit: ZAILimit?

        for limit in limits {
            guard let line = mapLimit(limit) else { continue }
            lines.append(line)

            // Track for headline priority (AC5)
            if limit.type == "TOKENS_LIMIT", limit.unit == 3 {
                fiveHourLimit = limit
            } else if limit.type == "TOKENS_LIMIT", limit.unit == 6 {
                weeklyLimit = limit
            }
        }

        let headline = computeHeadline(
            fiveHourLimit: fiveHourLimit,
            weeklyLimit: weeklyLimit
        )

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline,
            lines: lines,
            lastUpdated: Date(),
            peakHoursConfig: Self.peakHoursConfig
        )
    }

    /// Maps a single z.ai limit to a UsageLine, or nil when the (type, unit)
    /// pair is unrecognized (providers 01 AC2).
    private func mapLimit(_ limit: ZAILimit) -> UsageLine? {
        guard let labelKey = ZAILimitLabel.lookup(type: limit.type, unit: limit.unit) else {
            return nil
        }

        let resetDate = limit.nextResetTime.map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        }

        // z.ai overloads these fields by limit type:
        //  - token windows (unit 3/6): only `percentage`, no usage/currentValue
        //  - monthly web-tool line (unit 5): `currentValue` = actual used,
        //    `usage` = the allowance (cap), `remaining` = what's left. So here
        //    `currentValue` is "used" and `usage` is "total" — not the reverse.
        let used: Double?
        let total: Double?
        if let currentValue = limit.currentValue {
            used = currentValue
            total = limit.usage
        } else {
            used = limit.usage
            total = nil
        }

        let details = limit.usageDetails.map { details in
            details.map { detail in
                let value = if let usage = detail.usage {
                    String(format: "%.0f", usage)
                } else {
                    "—"
                }
                return UsageDetail(label: detail.modelCode, value: value)
            }
        }

        return UsageLine(
            label: String(localized: String.LocalizationValue(labelKey)),
            used: used,
            total: total,
            percentage: limit.percentage,
            unit: nil,
            resetDate: resetDate,
            details: details
        )
    }

    /// Builds the headline string using 5-hour → weekly priority (providers 01 AC5).
    private func computeHeadline(
        fiveHourLimit: ZAILimit?,
        weeklyLimit: ZAILimit?
    ) -> String {
        let primary = fiveHourLimit ?? weeklyLimit

        if let primary, let pct = primary.percentage {
            let pctString = String(format: "%.0f%%", pct)
            if let resetEpoch = primary.nextResetTime {
                let resetDate = Date(timeIntervalSince1970: Double(resetEpoch) / 1000)
                return "\(pctString) · \(QuotaFormatting.countdown(to: resetDate))"
            }
            return pctString
        }

        return String(localized: "No data")
    }
}
