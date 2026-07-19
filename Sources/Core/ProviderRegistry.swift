import Foundation

public final class ProviderRegistry {
    private var providers: [String: any AIProvider] = [:]
    private let keychain = Keychain.shared

    public init() {}

    public func register(_ provider: any AIProvider) {
        let id = type(of: provider).providerId
        providers[id] = provider
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
                        let quota = try await provider.fetchQuota(apiKey: apiKey)
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
