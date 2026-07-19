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

    public static func == (lhs: ZAIError, rhs: ZAIError) -> Bool {
        switch (lhs, rhs) {
        case (.missingKey, .missingKey): true
        case let (.http(lhsVal), .http(rhsVal)): lhsVal == rhsVal
        case let (.network(lhsVal), .network(rhsVal)): lhsVal.localizedDescription == rhsVal.localizedDescription
        case let (.decoding(lhsVal), .decoding(rhsVal)): lhsVal.localizedDescription == rhsVal.localizedDescription
        default: false
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

// MARK: - Provider

public struct ZAIProvider: AIProvider {
    public static let providerId = "zai"
    public static let providerName = "z.ai"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchQuota(apiKey: String) async throws -> ProviderQuota {
        guard !apiKey.isEmpty else {
            throw ZAIError.missingKey
        }

        var request = URLRequest(url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!)
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
            lastUpdated: Date()
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
