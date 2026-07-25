import Foundation

/// All mutation happens on the MainActor (`AppMain.init()` registers providers
/// before the view model reads them; `QuotaViewModel` is `@MainActor`).
/// MainActor isolation implies `Sendable` (SE-0306/SE-0338), so the registry
/// crosses `Task` boundaries without an `@unchecked` escape hatch.
@MainActor
public final class ProviderRegistry {
    private var providers: [String: any AIProvider] = [:]
    private let keychain = Keychain.shared

    public init() {}

    public func register(_ provider: any AIProvider) {
        let id = type(of: provider).providerId
        providers[id] = provider
    }

    public var registeredProviders: [ProviderInfo] {
        providers.values.map { provider in
            ProviderInfo(
                id: type(of: provider).providerId,
                displayName: type(of: provider).providerName,
                glyph: type(of: provider).providerGlyph,
                description: type(of: provider).providerDescription,
                disclaimer: type(of: provider).providerDisclaimer,
                defaultBaseURL: type(of: provider).baseURL,
                authShape: type(of: provider).authShape,
                setupHelp: type(of: provider).setupHelp,
                credentialImportActionTitle: type(of: provider).credentialImportActionTitle
            )
        }
    }

    /// For `.apiKey` providers this checks the Keychain; for `.apiKeyFree`
    /// providers it delegates to the provider's own `isConfigured()` — the
    /// provider owns what "configured" means for its auth shape.
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
        // Snapshot before crossing into the TaskGroup so child tasks never
        // touch MainActor-isolated state.
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

    // MARK: - Setup state

    /// Fires `currentSetupState()` on every registered `.apiKeyFree` provider
    /// concurrently. `.apiKey` providers are not called — their setup state is
    /// always `nil`. The view model calls this at launch and after
    /// install/uninstall actions to re-sync without blocking the main actor.
    public func refreshSetupStates() async -> [String: ProviderState] {
        // Snapshot before crossing into the TaskGroup so child tasks never
        // touch MainActor-isolated state.
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

    // MARK: - Helper management

    /// The popover uses this to suppress the "Clear Key" button.
    public func isAPIKeyFree(_ providerId: String) -> Bool {
        guard let provider = providers[providerId] else { return false }
        return type(of: provider).authShape == .apiKeyFree
    }

    /// `.apiKey` providers always return `false` — they have no helper.
    public func canInstallHelper(for providerId: String) -> Bool {
        guard let provider = providers[providerId] else { return false }
        return provider.canInstallHelper()
    }

    /// Throws when the provider is not registered or does not support helper
    /// installation.
    public func installHelper(for providerId: String) async throws {
        guard let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        try await provider.installHelper()
    }

    /// Throws when the provider is not registered or does not support helper
    /// removal.
    public func removeHelper(for providerId: String) async throws {
        guard let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        try await provider.removeHelper()
    }

    // MARK: - Credential import

    /// Returns `nil` when the provider does not support credential import.
    public func credentialImportActionTitle(for providerId: String) -> String? {
        providers[providerId].map { type(of: $0).credentialImportActionTitle } ?? nil
    }

    /// Routes an explicit credential import without inspecting a provider ID
    /// or provider-specific credential shape.
    public func importCredentials(for providerId: String) async throws {
        guard let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        try await provider.importCredentials()
    }

    // MARK: - Proactive refresh

    /// Throws `ProviderSetupError.notSupported` when the provider is not
    /// registered or does not conform. The view model catches this and
    /// proceeds straight to `fetchQuota`, so non-conforming providers are
    /// unaffected.
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
