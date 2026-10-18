import Core
import Foundation

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

extension ZAIError: UnderlyingErrorProviding {
    public var underlyingError: (any Error)? {
        switch self {
        case let .network(error), let .decoding(error):
            error
        default:
            nil
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
    public static var providerDescription: String {
        String(displayLocalized: "Monitor API usage and quotas", bundle: .module)
    }

    /// Host root for z.ai requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.z.ai")!

    private let session: URLSession
    private let errorLog: ErrorLog
    private let gate: ProviderRetryGate

    public var retryGate: ProviderRetryGate? {
        gate
    }

    public init(session: URLSession = .shared) {
        self.init(session: session, errorLog: .shared)
    }

    init(
        session: URLSession,
        errorLog: ErrorLog,
        retryGate: ProviderRetryGate = ProviderRetryGate()
    ) {
        self.session = session
        self.errorLog = errorLog
        gate = retryGate
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
        let receivedAt = Date()
        let subscriptionVersion = try await fetchSubscriptionVersion(baseURL: baseURL, apiKey: apiKey)
        return map(quotaResponse, subscriptionVersion: subscriptionVersion, receivedAt: receivedAt)
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
            throw ZAIError.decoding(error)
        }
    }

    /// Best-effort: any failure except a rate limit degrades to `nil`, which
    /// suppresses pricing metadata without failing the refresh. A `429` is
    /// rethrown so the cycle surfaces the backoff the scheduler must honor.
    private func fetchSubscriptionVersion(baseURL: URL, apiKey: String) async throws -> String? {
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("biz")
            .appendingPathComponent("subscription")
            .appendingPathComponent("list")
        let data: Data
        do {
            data = try await get(endpoint: endpoint, apiKey: apiKey)
        } catch ZAIError.http(404), ZAIError.http(405), ZAIError.http(501) {
            return nil
        } catch ZAIError.http(429) {
            throw ZAIError.http(429)
        } catch {
            guard !Task.isCancelled,
                  !(error is CancellationError)
            else { return nil }
            errorLog.record(
                component: "ZAIProvider",
                operation: "fetchSubscriptionVersion",
                code: "subscription_fetch_failed",
                providerID: Self.providerId
            )
            return nil
        }

        do {
            let response = try JSONDecoder().decode(ZAISubscriptionResponse.self, from: data)
            return response.data?.first { $0.status == "VALID" }?.version
        } catch {
            guard !Task.isCancelled else { return nil }
            errorLog.record(
                component: "ZAIProvider",
                operation: "decodeSubscriptionVersion",
                code: "subscription_decoding_failed",
                providerID: Self.providerId
            )
            return nil
        }
    }

    private func get(endpoint: URL, apiKey: String) async throws -> Data {
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
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ZAIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZAIError.network(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            recordRetryDeadline(from: httpResponse)
            throw ZAIError.http(httpResponse.statusCode)
        }
        return data
    }

    private func recordRetryDeadline(from response: HTTPURLResponse) {
        guard response.statusCode == 429 else { return }
        let header = response.value(forHTTPHeaderField: "Retry-After")
        guard let retryAfter = header.flatMap(TimeInterval.init), retryAfter > 0 else { return }
        gate.record(retryAfter: retryAfter)
    }
}
