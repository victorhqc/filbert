import Core
import Foundation

public struct KimiAPIProvider: AIProvider {
    public static let providerId = "kimi-api"
    public static let providerName = "Kimi API"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static var providerDescription: String {
        String(displayLocalized: "Monitor prepaid balance", bundle: .module)
    }

    /// Host root for Kimi Open Platform requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.moonshot.ai")!
    static let chinaBaseURL = URL(string: "https://api.moonshot.cn")!
    static let chinaConsoleHost = "platform.kimi.com"

    static let availableBalanceLineId = "available-balance"
    static let voucherBalanceLineId = "voucher-balance"
    static let cashBalanceLineId = "cash-balance"

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
            throw KimiAPIError.internalInconsistency
        }
        guard !apiKey.isEmpty else {
            throw KimiAPIError.missingKey
        }

        let endpoint = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("users")
            .appendingPathComponent("me")
            .appendingPathComponent("balance")
        let data = try await get(endpoint: endpoint, apiKey: apiKey)

        let response: KimiBalanceResponse
        do {
            response = try JSONDecoder().decode(KimiBalanceResponse.self, from: data)
        } catch {
            throw KimiAPIError.decoding(error)
        }

        guard response.code == 0, response.status != false, let balance = response.data else {
            throw KimiAPIError.rejected(code: response.code)
        }

        return map(balance, currency: Self.currency(for: baseURL), receivedAt: Date())
    }

    /// The balance response names no currency. Each platform bills in one
    /// currency, and its keys only work on its own host.
    static func currency(for baseURL: URL) -> String {
        baseURL.host?.lowercased() == chinaBaseURL.host ? "CNY" : "USD"
    }

    private func get(endpoint: URL, apiKey: String) async throws -> Data {
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
            throw KimiAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KimiAPIError.network(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            recordRetryDeadline(from: httpResponse)
            throw KimiAPIError.http(httpResponse.statusCode)
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
