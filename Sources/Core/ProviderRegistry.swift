import Foundation

public final class ProviderRegistry {
    private var providers: [String: any AIProvider] = [:]
    private let keychain = Keychain.shared

    public init() {}

    public func register(_ provider: any AIProvider) {
        let id = type(of: provider).providerId
        providers[id] = provider
    }

    /// List of all registered providers with their metadata (ui 02 AC2/AC9).
    public var registeredProviders: [ProviderInfo] {
        providers.values.map { provider in
            ProviderInfo(
                id: type(of: provider).providerId,
                displayName: type(of: provider).providerName,
                description: type(of: provider).providerDescription,
                defaultBaseURL: type(of: provider).baseURL
            )
        }
    }

    /// Whether the given provider has a saved API key in the Keychain (ui 02 AC3/AC5).
    public func isConfigured(_ providerId: String) -> Bool {
        (try? keychain.load(for: providerId)) != nil
    }

    public func fetchAll() async -> [String: Result<ProviderQuota, Error>] {
        let snapshot = providers
        let keychain = keychain

        return await withTaskGroup(
            of: (String, Result<ProviderQuota, Error>).self
        ) { group in
            for (id, provider) in snapshot {
                let providerId = id
                group.addTask {
                    do {
                        let apiKey = try keychain.load(for: providerId)
                        // Core resolves the effective URL: user override when
                        // present and valid, else the provider's default (core 02 AC2/AC6).
                        let baseURL = ProviderOverrides.baseURL(for: providerId)
                            ?? type(of: provider).baseURL
                        let quota = try await provider.fetchQuota(
                            apiKey: apiKey,
                            baseURL: baseURL
                        )
                        return (providerId, .success(quota))
                    } catch {
                        return (providerId, .failure(error))
                    }
                }
            }

            var results: [String: Result<ProviderQuota, Error>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
    }
}
