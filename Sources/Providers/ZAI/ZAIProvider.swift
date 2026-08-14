import Core
import Foundation

// MARK: - Diagnostic logging

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
    let windowDuration: TimeInterval?

    static let known: [ZAILimitLabel] = [
        ZAILimitLabel(
            type: "TOKENS_LIMIT",
            unit: 3,
            label: "5-hour window",
            windowDuration: UsageWindowDuration.fiveHours
        ),
        ZAILimitLabel(
            type: "TOKENS_LIMIT",
            unit: 6,
            label: "Weekly",
            windowDuration: UsageWindowDuration.week
        ),
        ZAILimitLabel(
            type: "TIME_LIMIT",
            unit: 5,
            label: "Monthly web-tool calls",
            windowDuration: nil
        ),
    ]

    static func lookup(type: String, unit: Int) -> ZAILimitLabel? {
        known.first { $0.type == type && $0.unit == unit }
    }
}

// MARK: - Peak-hours metadata

/// GLM Coding Plan peak-hours rules sourced from zai-bar's README.
/// Last verified: 2026-07-21.
public enum ZAIPeakHours {
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai")

    public static let windows = [
        PeakHoursWindow(startHour: 14, endHour: 18),
    ]
    public static let peakMultiplier = 3
    public static let offPeakMultiplier = 2
    public static let promoMultiplier = 1

    /// After this date the off-peak multiplier flips from `promoMultiplier`
    /// to `offPeakMultiplier`.
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
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(localized: "Monitor API usage and quotas")
    /// Host root for z.ai requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.z.ai")!

    public static let peakHoursConfig = PeakHoursConfig(
        timeZone: ZAIPeakHours.timeZone,
        windows: ZAIPeakHours.windows,
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
            throw ZAIError.internalInconsistency
        }

        guard !apiKey.isEmpty else {
            throw ZAIError.missingKey
        }

        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("monitor")
            .appendingPathComponent("usage")
            .appendingPathComponent("quota")
            .appendingPathComponent("limit")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        // z.ai's monitor endpoint expects the raw token, NOT an
        // "Authorization: Bearer …" scheme. Sending a "Bearer " prefix is
        // rejected as unauthenticated. This holds for both regular API and
        // Coding Plan keys — the endpoint is plan-agnostic.
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
            activityObservation: activityObservation(from: limits),
            peakHoursConfig: Self.peakHoursConfig
        )
    }

    private func activityObservation(from limits: [ZAILimit]) -> ProviderActivityObservation {
        let metrics = limits.compactMap { limit -> ProviderActivityMetric? in
            guard let id = activityMetricID(for: limit),
                  let value = limit.currentValue ?? limit.usage ?? limit.percentage
            else {
                return nil
            }
            return ProviderActivityMetric(
                id: id,
                kind: .usage,
                value: .number(Decimal(value))
            )
        }
        return ProviderActivityObservation(metrics: metrics)
    }

    private func activityMetricID(for limit: ZAILimit) -> String? {
        switch (limit.type, limit.unit) {
        case ("TOKENS_LIMIT", 3):
            "five-hour-usage"
        case ("TOKENS_LIMIT", 6):
            "weekly-usage"
        case ("TIME_LIMIT", 5):
            "monthly-web-tool-usage"
        default:
            nil
        }
    }

    private func mapLimit(_ limit: ZAILimit) -> UsageLine? {
        guard let limitLabel = ZAILimitLabel.lookup(type: limit.type, unit: limit.unit) else {
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
            label: String(localized: String.LocalizationValue(limitLabel.label)),
            used: used,
            total: total,
            percentage: limit.percentage,
            unit: nil,
            resetDate: resetDate,
            windowDuration: limitLabel.windowDuration,
            details: details
        )
    }

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
