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
                glyph: type(of: provider).providerGlyph,
                description: type(of: provider).providerDescription,
                defaultBaseURL: type(of: provider).baseURL,
                authShape: type(of: provider).authShape,
                setupHelp: type(of: provider).setupHelp
            )
        }
    }

    /// Whether the given provider is ready to fetch (ui 02 AC3/AC5, core 03 AC5).
    ///
    /// For `.apiKey` providers this checks the Keychain. For `.apiKeyFree`
    /// providers this delegates to the provider's own `isConfigured()` —
    /// the provider owns what "configured" means for its auth shape.
    public func isConfigured(_ providerId: String) -> Bool {
        guard let provider = providers[providerId] else { return false }
        let shape = type(of: provider).authShape
        switch shape {
        case .apiKey:
            return (try? keychain.load(for: providerId)) != nil
        case .apiKeyFree:
            return provider.isConfigured()
        }
    }

    public func fetchAll() async -> [String: Result<ProviderQuota, Error>] {
        let snapshot = providers
        let keychain = keychain

        return await withTaskGroup(
            of: (String, Result<ProviderQuota, Error>).self
        ) { group in
            for (id, provider) in snapshot {
                let providerId = id
                let shape = type(of: provider).authShape
                group.addTask {
                    do {
                        let auth: ProviderAuth
                        switch shape {
                        case .apiKey:
                            let apiKey = try keychain.load(for: providerId)
                            auth = .apiKey(apiKey)
                        case .apiKeyFree:
                            auth = .apiKeyFree
                        }
                        // Core resolves the effective URL: user override when
                        // present and valid, else the provider's default (core 02 AC2/AC6).
                        let baseURL = ProviderOverrides.baseURL(for: providerId)
                            ?? type(of: provider).baseURL
                        let quota = try await provider.fetchQuota(
                            auth: auth,
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

    // MARK: - Setup state (core 03 AC6)

    /// Fires `currentSetupState()` on every registered `.apiKeyFree` provider
    /// concurrently. `.apiKey` providers are not called — their setup state
    /// is always `nil` (core 03 AC6).
    ///
    /// The view model calls this at launch and after install/uninstall actions
    /// to re-sync setup state without blocking the main actor.
    public func refreshSetupStates() async -> [String: ProviderState] {
        let snapshot = providers

        return await withTaskGroup(
            of: (String, ProviderState?).self
        ) { group in
            for (id, provider) in snapshot {
                let providerId = id
                let shape = type(of: provider).authShape
                guard shape == .apiKeyFree else { continue }
                group.addTask {
                    let state = await provider.currentSetupState()
                    return (providerId, state)
                }
            }

            var results: [String: ProviderState] = [:]
            for await (id, state) in group {
                if let state {
                    results[id] = state
                }
            }
            return results
        }
    }

    // MARK: - Helper management (ui 05)

    /// Returns `true` when the provider's auth shape is `.apiKeyFree`
    /// (ui 05 AC8). The popover uses this to suppress the "Clear Key" button.
    public func isAPIKeyFree(_ providerId: String) -> Bool {
        guard let provider = providers[providerId] else { return false }
        return type(of: provider).authShape == .apiKeyFree
    }

    /// Returns `true` when the `.apiKeyFree` provider's helper can be
    /// installed right now (binary is present). `.apiKey` providers always
    /// return `false` — they have no helper (ui 05 AC3/AC4).
    public func canInstallHelper(for providerId: String) -> Bool {
        guard let provider = providers[providerId] else { return false }
        return provider.canInstallHelper()
    }

    /// Delegates to the provider's `installHelper()`. Throws when the
    /// provider is not registered or does not support helper installation
    /// (ui 05 AC4).
    public func installHelper(for providerId: String) async throws {
        guard let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        try await provider.installHelper()
    }

    /// Delegates to the provider's `removeHelper()`. Throws when the
    /// provider is not registered or does not support helper removal
    /// (ui 05 AC5).
    public func removeHelper(for providerId: String) async throws {
        guard let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        try await provider.removeHelper()
    }

    // MARK: - Proactive refresh (providers 03)

    /// Triggers an out-of-band refresh on providers that conform to
    /// `ProactiveRefreshable` (providers 03 AC3). Throws
    /// `ProviderSetupError.notSupported` when the provider is not registered
    /// or does not conform — the view model catches this and proceeds
    /// straight to `fetchQuota`, so non-conforming providers behave
    /// identically to before.
    public func proactiveRefresh(for providerId: String) async throws {
        guard let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        guard let refreshable = provider as? ProactiveRefreshable else {
            throw ProviderSetupError.notSupported
        }
        try await refreshable.proactiveRefresh()
    }
}
