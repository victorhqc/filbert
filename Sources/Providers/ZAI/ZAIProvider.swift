import Core
import Foundation

// MARK: - Error

enum ZAIError: Error, Equatable, Sendable {
    case missingKey
    case http(Int)
    case network(Error)
    case decoding(Error)

    static func == (lhs: ZAIError, rhs: ZAIError) -> Bool {
        switch (lhs, rhs) {
        case (.missingKey, .missingKey): true
        case let (.http(l), .http(r)): l == r
        case let (.network(l), .network(r)): l.localizedDescription == r.localizedDescription
        case let (.decoding(l), .decoding(r)): l.localizedDescription == r.localizedDescription
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
    let nextResetTime: Int64?
    let usageDetails: [ZAIUsageDetail]?
}

private struct ZAIUsageDetail: Decodable {
    let model: String
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

struct ZAIProvider: AIProvider {
    static let providerId = "zai"
    static let providerName = "z.ai"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuota(apiKey: String) async throws -> ProviderQuota {
        guard !apiKey.isEmpty else {
            throw ZAIError.missingKey
        }

        var request = URLRequest(url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZAIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZAIError.network(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            throw ZAIError.http(httpResponse.statusCode)
        }

        let quotaResponse: ZAIQuotaResponse
        do {
            quotaResponse = try JSONDecoder().decode(ZAIQuotaResponse.self, from: data)
        } catch {
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
            guard let labelKey = ZAILimitLabel.lookup(type: limit.type, unit: limit.unit) else {
                continue // AC2: unrecognized pairs are ignored
            }

            let resetDate = limit.nextResetTime.map {
                Date(timeIntervalSince1970: Double($0) / 1000)
            }

            let used = limit.usage ?? limit.currentValue
            let details = limit.usageDetails.map { details in
                details.map { detail in
                    let value: String = if let usage = detail.usage {
                        String(format: "%.0f", usage)
                    } else {
                        "—"
                    }
                    return UsageDetail(label: detail.model, value: value)
                }
            }

            let line = UsageLine(
                label: String(localized: String.LocalizationValue(labelKey)),
                used: used,
                percentage: limit.percentage,
                unit: nil,
                resetDate: resetDate,
                details: details
            )
            lines.append(line)

            // Track for headline priority (AC5)
            if limit.type == "TOKENS_LIMIT" && limit.unit == 3 {
                fiveHourLimit = limit
            } else if limit.type == "TOKENS_LIMIT" && limit.unit == 6 {
                weeklyLimit = limit
            }
        }

        // AC5: headline follows 5-hour → weekly priority
        let primary = fiveHourLimit ?? weeklyLimit
        let headline: String

        if let primary, let pct = primary.percentage {
            let pctString = String(format: "%.0f%%", pct)
            if let resetEpoch = primary.nextResetTime {
                let resetDate = Date(timeIntervalSince1970: Double(resetEpoch) / 1000)
                headline = "\(pctString) · \(QuotaFormatting.countdown(to: resetDate))"
            } else {
                headline = pctString
            }
        } else {
            headline = String(localized: "No data")
        }

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline,
            lines: lines,
            lastUpdated: Date()
        )
    }
}
