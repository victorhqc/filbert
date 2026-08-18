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

// MARK: - Peak-hours metadata

public enum ZAIPeakHours {
    /// Legacy V2 calculation: daily 14:00–18:00 China Standard Time at
    /// 3× peak / 1× off-peak.
    public static let legacyV2 = PeakHoursConfig(
        timeZone: TimeZone(identifier: "Asia/Shanghai"),
        windows: [PeakHoursWindow(startHour: 14, endHour: 18)],
        peakMultiplier: 3,
        offPeakMultiplier: 1
    )

    /// Credits calculation: Mon–Fri 14:00–18:00 Singapore time, with off-peak
    /// consumption at 50% of the standard credit rate.
    public static let credits = PeakHoursConfig(
        timeZone: TimeZone(identifier: "Asia/Singapore"),
        windows: [PeakHoursWindow(startHour: 14, endHour: 18, weekdays: [2, 3, 4, 5, 6])],
        peakRate: .fractionOfStandardRate(1),
        offPeakRate: .fractionOfStandardRate(0.5)
    )
}

// MARK: - Provider

public struct ZAIProvider: AIProvider {
    public static let providerId = "zai"
    public static let providerName = "z.ai"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(localized: "Monitor API usage and quotas")
    /// Host root for z.ai requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.z.ai")!

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

        let quotaResponse = try await fetchQuotaResponse(baseURL: baseURL, apiKey: apiKey)
        let subscriptionVersion = await fetchSubscriptionVersion(baseURL: baseURL, apiKey: apiKey)
        return map(quotaResponse, subscriptionVersion: subscriptionVersion)
    }

    private func fetchQuotaResponse(baseURL: URL, apiKey: String) async throws -> ZAIQuotaResponse {
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("monitor")
            .appendingPathComponent("usage")
            .appendingPathComponent("quota")
            .appendingPathComponent("limit")
        let data = try await get(endpoint: endpoint, apiKey: apiKey)

        do {
            return try JSONDecoder().decode(ZAIQuotaResponse.self, from: data)
        } catch {
            ZAILog.log("decoding error: \(error)")
            throw ZAIError.decoding(error)
        }
    }

    /// Best-effort: any failure degrades to `nil`, which suppresses pricing
    /// metadata without failing the refresh.
    private func fetchSubscriptionVersion(baseURL: URL, apiKey: String) async -> String? {
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("biz")
            .appendingPathComponent("subscription")
            .appendingPathComponent("list")
        let data: Data
        do {
            data = try await get(endpoint: endpoint, apiKey: apiKey, logsBody: false)
        } catch {
            ZAILog.log("subscription fetch failed: \(error)")
            return nil
        }

        do {
            let response = try JSONDecoder().decode(ZAISubscriptionResponse.self, from: data)
            return response.data?.first { $0.status == "VALID" }?.version
        } catch {
            ZAILog.log("subscription decoding error: \(error)")
            return nil
        }
    }

    private func get(endpoint: URL, apiKey: String, logsBody: Bool = true) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        // z.ai's monitor endpoints expect the raw token, NOT an
        // "Authorization: Bearer …" scheme. Sending a "Bearer " prefix is
        // rejected as unauthenticated. This holds for both regular API and
        // Coding Plan keys — the endpoints are plan-agnostic.
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

        if logsBody {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
            ZAILog.log("status=\(httpResponse.statusCode) body=\(bodyPreview)")
        } else {
            ZAILog.log("status=\(httpResponse.statusCode) bytes=\(data.count)")
        }

        guard httpResponse.statusCode == 200 else {
            throw ZAIError.http(httpResponse.statusCode)
        }
        return data
    }

    // MARK: - Mapping

    private func map(_ response: ZAIQuotaResponse, subscriptionVersion: String?) -> ProviderQuota {
        let limits = response.data.limits
        var lines: [UsageLine] = []
        var fiveHourLimit: ZAILimit?
        var weeklyLimit: ZAILimit?

        for limit in limits {
            guard let window = ZAIWindowDescriptor.recognize(limit) else { continue }
            lines.append(mapLimit(limit, window: window))

            if window.isFiveHour {
                fiveHourLimit = limit
            } else if window.isWeekly {
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
            peakHoursConfig: Self.peakHoursConfig(for: limits, subscriptionVersion: subscriptionVersion)
        )
    }

    /// A credits-shaped response identifies the credits calculation on its
    /// own; a tokens-shaped response is only legacy V2 when the subscription
    /// endpoint positively reports version "V2". Anything else — mixed
    /// shapes, unknown versions, or a failed subscription fetch — gets no
    /// pricing metadata.
    private static func peakHoursConfig(
        for limits: [ZAILimit],
        subscriptionVersion: String?
    ) -> PeakHoursConfig? {
        let types = Set(limits.map(\.type))
        let hasCreditWindows = types.contains(ZAILimitType.credits.rawValue)
        let hasTokenWindows = types.contains(ZAILimitType.tokens.rawValue)

        if hasCreditWindows, !hasTokenWindows {
            return ZAIPeakHours.credits
        }
        if hasTokenWindows, !hasCreditWindows, subscriptionVersion == "V2" {
            return ZAIPeakHours.legacyV2
        }
        return nil
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
        switch (ZAILimitType(rawValue: limit.type), limit.unit) {
        case (.tokens, 3), (.credits, 3):
            "five-hour-usage"
        case (.tokens, 6), (.credits, 6):
            "weekly-usage"
        case (.time, 5):
            "monthly-web-tool-usage"
        default:
            nil
        }
    }

    private func mapLimit(_ limit: ZAILimit, window: ZAIWindowDescriptor) -> UsageLine {
        let resetDate = limit.nextResetTime.map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        }

        // z.ai overloads these fields by limit type:
        //  - token windows (unit 3/6): only `percentage`, no usage/currentValue
        //  - credit windows (unit 3/6): `currentValue` = credits used,
        //    `usage` = the credit allowance
        //  - monthly web-tool line (unit 5): `currentValue` = actual used,
        //    `usage` = the allowance (cap), `remaining` = what's left.
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
            label: window.label,
            used: used,
            total: total,
            percentage: limit.percentage,
            unit: nil,
            resetDate: resetDate,
            windowDuration: window.windowDuration,
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
