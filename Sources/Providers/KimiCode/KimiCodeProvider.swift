import Core
import Foundation

public struct KimiCodeProvider: AIProvider {
    public static let providerId = "kimi-code"
    public static let providerName = "Kimi Code"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static var providerDescription: String {
        String(displayLocalized: "Monitor Kimi Code usage limits", bundle: .module)
    }

    /// Host root for Kimi Code requests; path segments live in `fetchQuota`.
    public static let baseURL = URL(string: "https://api.kimi.ai")!
    static let chinaBaseURL = URL(string: "https://api.kimi.com")!

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
            throw KimiCodeError.internalInconsistency
        }
        guard !apiKey.isEmpty else {
            throw KimiCodeError.missingKey
        }

        let endpoint = baseURL
            .appendingPathComponent("coding")
            .appendingPathComponent("v1")
            .appendingPathComponent("usages")
        let data = try await get(endpoint: endpoint, apiKey: apiKey)

        let response: KimiCodeUsagesResponse
        do {
            response = try JSONDecoder().decode(KimiCodeUsagesResponse.self, from: data)
        } catch {
            throw KimiCodeError.decoding(error)
        }

        return map(response, receivedAt: Date())
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
            throw KimiCodeError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KimiCodeError.network(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            recordRetryDeadline(from: httpResponse)
            throw KimiCodeError.http(httpResponse.statusCode)
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
