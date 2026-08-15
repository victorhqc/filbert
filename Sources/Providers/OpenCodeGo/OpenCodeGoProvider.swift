import Core
import Foundation

enum OpenCodeGoLog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[OpenCodeGoProvider] \(message())\n".utf8))
    }
}

public enum OpenCodeGoError: Error, Equatable, Sendable {
    case missingKey
    case untrustedBaseURL
    case authenticationFailed
    case noSubscription
    case rateLimited
    case http(Int)
    case network(Error)
    case decoding(Error)
    case internalInconsistency

    public static func == (lhs: OpenCodeGoError, rhs: OpenCodeGoError) -> Bool {
        switch (lhs, rhs) {
        case (.missingKey, .missingKey),
             (.untrustedBaseURL, .untrustedBaseURL),
             (.authenticationFailed, .authenticationFailed),
             (.noSubscription, .noSubscription),
             (.rateLimited, .rateLimited),
             (.internalInconsistency, .internalInconsistency):
            true
        case let (.http(lhsStatus), .http(rhsStatus)):
            lhsStatus == rhsStatus
        case let (.network(lhsError), .network(rhsError)):
            lhsError.localizedDescription == rhsError.localizedDescription
        case let (.decoding(lhsError), .decoding(rhsError)):
            lhsError.localizedDescription == rhsError.localizedDescription
        default:
            false
        }
    }
}

extension OpenCodeGoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingKey:
            String(localized: "No API key configured.")
        case .untrustedBaseURL:
            String(localized: "OpenCode Go usage must be fetched from opencode.ai.")
        case .authenticationFailed:
            String(localized: "Authentication failed. Check your API key.")
        case .noSubscription:
            String(localized: "No OpenCode Go subscription.")
        case .rateLimited:
            String(localized: "Rate limited. Try again later.")
        case .network:
            String(localized: "Network error. Check your connection.")
        case .decoding, .http:
            String(localized: "Unexpected response from server.")
        case .internalInconsistency:
            String(localized: "Internal error: unexpected auth shape.")
        }
    }
}

private struct OpenCodeGoUsageResponse: Decodable {
    let usage: OpenCodeGoUsage
}

private struct OpenCodeGoUsage: Decodable {
    let rolling: OpenCodeGoUsageWindow
    let weekly: OpenCodeGoUsageWindow
    let monthly: OpenCodeGoUsageWindow
}

private struct OpenCodeGoUsageWindow: Decodable {
    let status: String
    let percent: Double
    let resetsAt: Date
}

private final class OpenCodeGoRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
              OpenCodeGoProvider.isTrusted(redirectedURL)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

actor OpenCodeGoRateLimitBackoff {
    private let baseDelay: TimeInterval
    private let maximumDelay: TimeInterval
    private let now: @Sendable () -> Date

    private var consecutiveRateLimits = 0
    private var nextAllowedRequest: Date?

    init(
        baseDelay: TimeInterval = 300,
        maximumDelay: TimeInterval = 3600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.now = now
    }

    func checkRequestAllowed() throws {
        guard let nextAllowedRequest, now() < nextAllowedRequest else { return }
        throw OpenCodeGoError.rateLimited
    }

    func recordRateLimit() {
        let exponent = min(consecutiveRateLimits, 10)
        let delay = min(baseDelay * pow(2, Double(exponent)), maximumDelay)
        consecutiveRateLimits += 1
        nextAllowedRequest = now().addingTimeInterval(delay)
    }

    func recordSuccessfulResponse() {
        consecutiveRateLimits = 0
        nextAllowedRequest = nil
    }
}

public struct OpenCodeGoProvider: AIProvider {
    public static let providerId = "opencode-go"
    public static let providerName = "OpenCode Go"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(localized: "Monitor OpenCode Go subscription usage")
    public static let baseURL = URL(string: "https://opencode.ai")!

    private static let monthlyWindowDuration: TimeInterval = 30 * 24 * 60 * 60

    private let session: URLSession
    private let rateLimitBackoff: OpenCodeGoRateLimitBackoff

    public init(session: URLSession = .shared) {
        self.init(session: session, rateLimitBackoff: OpenCodeGoRateLimitBackoff())
    }

    init(session: URLSession, rateLimitBackoff: OpenCodeGoRateLimitBackoff) {
        self.session = session
        self.rateLimitBackoff = rateLimitBackoff
    }

    public func fetchQuota(auth: ProviderAuth, baseURL: URL) async throws -> ProviderQuota {
        let apiKey = try apiKey(from: auth)
        let endpoint = try Self.usageEndpoint(from: baseURL)
        try await rateLimitBackoff.checkRequestAllowed()
        let request = Self.request(for: endpoint, apiKey: apiKey)
        let (data, response) = try await response(for: request)
        try await validate(response)
        let usage = try decode(data)
        return map(usage)
    }

    private func map(_ response: OpenCodeGoUsageResponse) -> ProviderQuota {
        let windows = [
            (
                id: "rolling-window-usage",
                label: String(localized: "5-hour window"),
                duration: UsageWindowDuration.fiveHours,
                usage: response.usage.rolling
            ),
            (
                id: "weekly-window-usage",
                label: String(localized: "Weekly"),
                duration: UsageWindowDuration.week,
                usage: response.usage.weekly
            ),
            (
                id: "monthly-window-usage",
                label: String(localized: "Monthly"),
                duration: Self.monthlyWindowDuration,
                usage: response.usage.monthly
            ),
        ]

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: String(localized: "OpenCode Go usage"),
            lines: windows.map { window in
                UsageLine(
                    label: window.label,
                    percentage: window.usage.percent,
                    resetDate: window.usage.resetsAt,
                    windowDuration: window.duration,
                    details: details(for: window.usage.status)
                )
            },
            lastUpdated: Date(),
            activityObservation: ProviderActivityObservation(
                metrics: windows.map { window in
                    ProviderActivityMetric(
                        id: window.id,
                        kind: .usage,
                        value: .number(Decimal(window.usage.percent))
                    )
                }
            )
        )
    }

    private func details(for status: String) -> [UsageDetail]? {
        switch status {
        case "ok":
            nil
        case "rate-limited":
            [UsageDetail(
                label: String(localized: "Status"),
                value: String(localized: "Rate limited")
            )]
        default:
            [UsageDetail(
                label: String(localized: "Status"),
                value: String(localized: "Unknown status")
            )]
        }
    }

    private func apiKey(from auth: ProviderAuth) throws -> String {
        let apiKey: String
        switch auth {
        case let .apiKey(key):
            apiKey = key
        case .apiKeyFree:
            throw OpenCodeGoError.internalInconsistency
        }
        guard !apiKey.isEmpty else {
            throw OpenCodeGoError.missingKey
        }
        return apiKey
    }

    private static func usageEndpoint(from baseURL: URL) throws -> URL {
        guard isTrusted(baseURL) else {
            throw OpenCodeGoError.untrustedBaseURL
        }
        return baseURL
            .appendingPathComponent("zen")
            .appendingPathComponent("go")
            .appendingPathComponent("v1")
            .appendingPathComponent("usage")
    }

    private static func request(for endpoint: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let requestStartedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: OpenCodeGoRedirectGuard())
        } catch {
            OpenCodeGoLog.log("network error after \(Date().timeIntervalSince(requestStartedAt))s: \(error)")
            throw OpenCodeGoError.network(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            OpenCodeGoLog.log("non-HTTP response after \(Date().timeIntervalSince(requestStartedAt))s")
            throw OpenCodeGoError.network(URLError(.badServerResponse))
        }
        OpenCodeGoLog.log(
            "status=\(httpResponse.statusCode) latency=\(Date().timeIntervalSince(requestStartedAt))s"
        )
        return (data, httpResponse)
    }

    private func validate(_ response: HTTPURLResponse) async throws {
        if response.statusCode == 429 {
            await rateLimitBackoff.recordRateLimit()
            throw OpenCodeGoError.rateLimited
        }
        await rateLimitBackoff.recordSuccessfulResponse()

        switch response.statusCode {
        case 200:
            return
        case 401:
            throw OpenCodeGoError.authenticationFailed
        case 403:
            throw OpenCodeGoError.noSubscription
        default:
            throw OpenCodeGoError.http(response.statusCode)
        }
    }

    private func decode(_ data: Data) throws -> OpenCodeGoUsageResponse {
        do {
            return try Self.decoder.decode(OpenCodeGoUsageResponse.self, from: data)
        } catch {
            OpenCodeGoLog.log("decoding error: \(error)")
            throw OpenCodeGoError.decoding(error)
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO-8601 reset timestamp."
                )
            }
            return date
        }
        return decoder
    }

    fileprivate static func isTrusted(_ baseURL: URL) -> Bool {
        baseURL.scheme?.lowercased() == "https"
            && baseURL.host?.lowercased() == "opencode.ai"
    }
}
