import Foundation

/// All mutation happens on the MainActor (`AppMain.init()` registers providers
/// before the view model reads them; `QuotaViewModel` is `@MainActor`).
/// MainActor isolation implies `Sendable` (SE-0306/SE-0338), so the registry
/// crosses `Task` boundaries without an `@unchecked` escape hatch.
@MainActor
public final class ProviderRegistry {
    private var providers: [String: any AIProvider] = [:]
    private let keychain: Keychain

    public init(keychain: Keychain = .shared) {
        self.keychain = keychain
    }

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
                automaticRefreshDisclosure: type(of: provider).automaticRefreshDisclosure,
                defaultBaseURL: type(of: provider).baseURL,
                authShape: type(of: provider).authShape,
                setupHelp: type(of: provider).setupHelp,
                credentialImportActionTitle: type(of: provider).credentialImportActionTitle
            )
        }
    }

    public func isEnabled(_ providerId: String) -> Bool {
        guard let provider = providers[providerId] else { return false }
        return ProviderEnablement.isEnabled(
            for: providerId,
            authShape: type(of: provider).authShape,
            keychain: keychain
        )
    }

    public func setEnabled(_ enabled: Bool, for providerId: String) {
        guard providers[providerId] != nil else { return }
        ProviderEnablement.setEnabled(enabled, for: providerId)
    }

    /// For `.apiKey` providers this checks the Keychain; for `.apiKeyFree`
    /// providers it delegates to the provider's own `isConfigured()` — the
    /// provider owns what "configured" means for its auth shape.
    public func isConfigured(_ providerId: String) -> Bool {
        guard isEnabled(providerId), let provider = providers[providerId] else { return false }
        let shape = type(of: provider).authShape
        switch shape {
        case .apiKey:
            return (try? keychain.load(for: providerId)) != nil
        case .apiKeyFree:
            return provider.isConfigured()
        }
    }

    public func fetchAll() async -> [String: Result<ProviderQuota, Error>] {
        let requests = providers.keys.compactMap(fetchRequest(for:))

        return await withTaskGroup(
            of: (String, Result<ProviderQuota, Error>).self
        ) { group in
            for request in requests {
                group.addTask {
                    await Self.fetch(request)
                }
            }

            var results: [String: Result<ProviderQuota, Error>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
    }

    public func fetchQuota(
        for providerId: String
    ) async -> Result<ProviderQuota, Error>? {
        guard let request = fetchRequest(for: providerId) else { return nil }
        let (_, result) = await Self.fetch(request)
        return result
    }

    // MARK: - Setup state

    /// Fires `currentSetupState()` on every registered `.apiKeyFree` provider
    /// concurrently. `.apiKey` providers are not called — their setup state is
    /// always `nil`; disabled providers are excluded before their state is read.
    public func refreshSetupStates() async -> [String: ProviderState] {
        let snapshot = providers.compactMap { providerId, provider -> (String, any AIProvider)? in
            guard type(of: provider).authShape == .apiKeyFree,
                  isEnabled(providerId)
            else {
                return nil
            }
            return (providerId, provider)
        }

        return await withTaskGroup(
            of: (String, ProviderState?).self
        ) { group in
            for (providerId, provider) in snapshot {
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

    public func refreshSetupState(for providerId: String) async -> ProviderState? {
        guard isEnabled(providerId),
              let provider = providers[providerId],
              type(of: provider).authShape == .apiKeyFree
        else {
            return nil
        }
        return await provider.currentSetupState()
    }

    // MARK: - Helper management

    /// The popover uses this to suppress the "Clear Key" button.
    public func isAPIKeyFree(_ providerId: String) -> Bool {
        guard let provider = providers[providerId] else { return false }
        return type(of: provider).authShape == .apiKeyFree
    }

    /// `.apiKey` providers always return `false` — they have no helper.
    public func canInstallHelper(for providerId: String) -> Bool {
        guard isEnabled(providerId), let provider = providers[providerId] else { return false }
        return provider.canInstallHelper()
    }

    /// Throws when the provider is not registered or does not support helper
    /// installation.
    public func installHelper(for providerId: String) async throws {
        guard isEnabled(providerId), let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        try await provider.installHelper()
    }

    /// Throws when the provider is not registered or does not support helper
    /// removal.
    public func removeHelper(for providerId: String) async throws {
        guard isEnabled(providerId), let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        try await provider.removeHelper()
    }

    // MARK: - Credential import

    /// Returns `nil` when the provider does not support credential import.
    public func credentialImportActionTitle(for providerId: String) -> String? {
        guard isEnabled(providerId), let provider = providers[providerId] else { return nil }
        return type(of: provider).credentialImportActionTitle
    }

    /// Routes an explicit credential import without inspecting a provider ID
    /// or provider-specific credential shape.
    public func importCredentials(for providerId: String) async throws {
        guard isEnabled(providerId), let provider = providers[providerId] else {
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
        guard isEnabled(providerId), let provider = providers[providerId] else {
            throw ProviderSetupError.notSupported
        }
        guard let refreshable = provider as? ProactiveRefreshable else {
            throw ProviderSetupError.notSupported
        }
        try await refreshable.proactiveRefresh()
    }
}

private extension ProviderRegistry {
    struct FetchRequest: Sendable {
        let providerId: String
        let provider: any AIProvider
        let authShape: ProviderAuth.Shape
        let keychain: Keychain

        func authentication() throws -> ProviderAuth {
            switch authShape {
            case .apiKey:
                let apiKey = try keychain.load(for: providerId)
                return .apiKey(apiKey)
            case .apiKeyFree:
                return .apiKeyFree
            }
        }
    }

    func fetchRequest(for providerId: String) -> FetchRequest? {
        guard isEnabled(providerId),
              isConfigured(providerId),
              let provider = providers[providerId]
        else {
            return nil
        }
        return FetchRequest(
            providerId: providerId,
            provider: provider,
            authShape: type(of: provider).authShape,
            keychain: keychain
        )
    }

    nonisolated static func fetch(
        _ request: FetchRequest
    ) async -> (String, Result<ProviderQuota, Error>) {
        do {
            let auth = try request.authentication()
            let baseURL = ProviderOverrides.baseURL(for: request.providerId)
                ?? type(of: request.provider).baseURL
            let quota = try await request.provider.fetchQuota(auth: auth, baseURL: baseURL)
            return (request.providerId, .success(quota))
        } catch {
            return (request.providerId, .failure(error))
        }
    }
}
