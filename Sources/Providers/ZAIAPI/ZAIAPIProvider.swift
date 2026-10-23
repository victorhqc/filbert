import Core
import Foundation

public struct ZAIAPIProvider: AIProvider {
    public static let providerId = "zai-api"
    public static let providerName = "z.ai API"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static var providerDescription: String {
        String(displayLocalized: "Monitor pay-as-you-go balance", bundle: .module)
    }

    public static var providerDisclaimer: String? {
        String(
            displayLocalized: """
            Use a Standard API key. Coding Plan usage is shown by the z.ai provider. \
            For BigModel (\(bigModelHost)) accounts, set the base URL to \(bigModelBaseURL.absoluteString).
            """,
            bundle: .module
        )
    }

    /// Host root for z.ai requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.z.ai")!
    static let bigModelBaseURL = URL(string: "https://open.bigmodel.cn")!
    static let bigModelHost = "bigmodel.cn"

    static let availableBalanceLineId = "available-balance"
    static let frozenBalanceLineId = "frozen-balance"
    static let totalSpendLineId = "total-spend"

    private let session: URLSession
    private let gate: ProviderRetryGate

    public var retryGate: ProviderRetryGate? {
        gate
    }

    public init(session: URLSession = .shared) {
        self.init(session: session, retryGate: ProviderRetryGate())
    }

    init(session: URLSession, retryGate: ProviderRetryGate) {
        self.session = session
        gate = retryGate
    }

    public func fetchQuota(auth: ProviderAuth, baseURL: URL) async throws -> ProviderQuota {
        guard case let .apiKey(apiKey) = auth else {
            throw ZAIAPIError.internalInconsistency
        }
        guard !apiKey.isEmpty else {
            throw ZAIAPIError.missingKey
        }

        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("biz")
            .appendingPathComponent("account")
            .appendingPathComponent("query-customer-account-report")
        let data = try await get(endpoint: endpoint, apiKey: apiKey)

        let envelope: ZAIAPIEnvelope
        do {
            envelope = try JSONDecoder().decode(ZAIAPIEnvelope.self, from: data)
        } catch {
            throw ZAIAPIError.decoding(error)
        }

        guard envelope.code == 200, envelope.success == true, let balance = envelope.data else {
            throw ZAIAPIError.rejected(code: envelope.code)
        }

        return map(balance, currency: Self.currency(for: baseURL), receivedAt: Date())
    }

    /// The report names no currency, and both hosts serve every account, so
    /// the host the user points at is the only signal.
    static func currency(for baseURL: URL) -> String {
        guard let host = baseURL.host?.lowercased() else { return "USD" }
        return host == bigModelHost || host.hasSuffix(".\(bigModelHost)") ? "CNY" : "USD"
    }

    /// z.ai accepts the key with or without a `Bearer` prefix.
    private func get(endpoint: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
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
            throw ZAIAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZAIAPIError.network(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            recordRetryDeadline(from: httpResponse)
            throw ZAIAPIError.http(httpResponse.statusCode)
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
