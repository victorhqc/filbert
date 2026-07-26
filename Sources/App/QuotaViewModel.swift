import Core
import Foundation
import Observation

@MainActor
@Observable
final class QuotaViewModel {
    // MARK: - Configuration

    private let keychain: Keychain
    let registry: ProviderRegistry
    let refreshInterval: TimeInterval = 300

    // MARK: - State

    /// Must be assigned as a whole value — dictionary subscript mutation
    /// does not trigger @Observable's setter.
    var providerStates: [String: ProviderState] = [:]

    /// Reassigned as a whole value so @Observable notifies observers —
    /// `ProviderOrder` and `registry` are not observable, so a computed property
    /// would not trigger re-renders.
    var orderedProviderIds: [String] = []

    var enabledProviderIds: Set<String> = []

    var configuredProviderIds: [String] = []

    var hasAnyConfiguredProvider: Bool = false

    /// Changing this token tells SwiftUI to re-resolve the UserDefaults-backed
    /// collapse values that live in Core.
    var collapseStateRevision = 0

    // MARK: - Quiet refresh

    var isRefreshing: [String: Bool] = [:]

    var refreshErrors: [String: String] = [:]

    // MARK: - Auto-refresh

    var refreshLoops: [String: Task<Void, Never>] = [:]

    var fetchTasks: [String: Task<Void, Never>] = [:]

    var setupTasks: [String: Task<Void, Never>] = [:]

    var lifecycleRevisions: [String: Int] = [:]

    // MARK: - Init

    init(
        keychain: Keychain = .shared,
        registry: ProviderRegistry
    ) {
        self.keychain = keychain
        self.registry = registry

        var enabledIds: Set<String> = []
        var configuredIds: Set<String> = []
        for info in registry.registeredProviders {
            guard registry.isEnabled(info.id) else {
                setState(.unconfigured, for: info.id)
                continue
            }
            enabledIds.insert(info.id)

            let configured = registry.isConfigured(info.id)
            log("init: provider=\(info.id) configured=\(configured)")
            setState(configured ? .loading : .unconfigured, for: info.id)
            if configured {
                configuredIds.insert(info.id)
            }
        }
        enabledProviderIds = enabledIds
        for providerId in configuredIds {
            startAutoRefresh(for: providerId)
        }

        recomputeOrderedProviderIds()
        refreshDerived()
        fetchAllQuotas()
        for info in registry.registeredProviders where info.authShape == .apiKeyFree {
            startEnabledProvider(for: info.id)
        }
    }

    // MARK: - Derived properties — public

    /// Display-name ascending is the fallback for fresh installs and newly
    /// registered providers. Reads `orderedProviderIds` (not `registry`) so
    /// SwiftUI re-renders when the order changes.
    var registeredProvidersOrdered: [ProviderInfo] {
        let byId = Dictionary(
            uniqueKeysWithValues: registry.registeredProviders.map { ($0.id, $0) }
        )
        return orderedProviderIds.compactMap { byId[$0] }
    }

    /// Shares the configured predicate with `refreshDerived()` (via
    /// `isConfiguredState`) so "what counts as configured" is defined in one place.
    var configuredProvidersOrdered: [ProviderInfo] {
        registeredProvidersOrdered.filter { info in
            isEnabled(info.id) && Self.isConfiguredState(providerStates[info.id])
        }
    }

    /// Must stay in sync with the states assigned by `init` and `setState(_:for:)`.
    static func isConfiguredState(_ state: ProviderState?) -> Bool {
        switch state {
        case .none, .unconfigured, .setup:
            false
        case .loading, .loaded, .error:
            true
        }
    }

    // MARK: - Key management

    func saveKey(_ key: String, for providerId: String) throws {
        try keychain.save(key, for: providerId)
        log("saveKey: provider=\(providerId)")
        setProviderEnabled(true, for: providerId)
    }

    func deleteKey(for providerId: String) throws {
        try keychain.delete(for: providerId)
        log("deleteKey: provider=\(providerId)")
        invalidateProviderWork(for: providerId)
        setState(.unconfigured, for: providerId)
        refreshDerived()
    }

    // MARK: - Base-URL override

    func overrideURL(for providerId: String) -> URL? {
        ProviderOverrides.baseURL(for: providerId)
    }

    func saveOverrideURL(_ url: URL?, for providerId: String) throws {
        guard !registry.isAPIKeyFree(providerId) else { return }
        try ProviderOverrides.setBaseURL(url, for: providerId)
        log("saveOverrideURL: provider=\(providerId) url=\(url?.absoluteString ?? "nil")")
        if isEnabled(providerId), registry.isConfigured(providerId) {
            performFetch(for: providerId)
        }
    }

    // MARK: - Fetch

    func fetchQuota(for providerId: String) {
        guard isReadyToFetch(providerId) else {
            log("fetchQuota: provider=\(providerId) is not ready, skipping")
            return
        }
        if case .loading = providerStates[providerId] {
            log("fetchQuota: provider=\(providerId) already loading, skipping")
            return
        }
        // debounce while refreshing
        if isRefreshing[providerId] == true {
            log("fetchQuota: provider=\(providerId) already refreshing, skipping")
            return
        }
        performFetch(for: providerId)
    }

    /// Runs the provider's proactive refresh before the cache read, so a single
    /// click both spawns the helper and re-reads the result. Auto-refresh and
    /// the initial fetch still call `fetchQuota(for:)` directly — proactive
    /// spawn is manual-only.
    func manualRefresh(for providerId: String) {
        guard isReadyToFetch(providerId) else {
            log("manualRefresh: provider=\(providerId) is not ready, skipping")
            return
        }
        if case .loading = providerStates[providerId] {
            log("manualRefresh: provider=\(providerId) already loading, skipping")
            return
        }
        // debounce while refreshing
        if isRefreshing[providerId] == true {
            log("manualRefresh: provider=\(providerId) already refreshing, skipping")
            return
        }

        switch providerStates[providerId] {
        case .loaded, .error:
            setRefreshing(true, for: providerId)
        default:
            setState(.loading, for: providerId)
            refreshDerived()
        }
        Task { [weak self] in
            await self?.performManualRefresh(providerId: providerId)
        }
    }

    /// Catches `.notSupported` from the proactive refresh so non-conforming
    /// providers fall through to the standard fetch path.
    private func performManualRefresh(providerId: String) async {
        do {
            try await registry.proactiveRefresh(for: providerId)
            log("performManualRefresh: provider=\(providerId) proactive refresh ok")
        } catch ProviderSetupError.notSupported {
            log("performManualRefresh: provider=\(providerId) does not support proactive refresh")
        } catch {
            log("performManualRefresh: provider=\(providerId) proactive refresh failed: \(error.localizedDescription)")
        }
        await MainActor.run { [weak self] in
            self?.performFetch(for: providerId)
        }
    }

    func fetchAllQuotas() {
        log("fetchAllQuotas: starting")
        let revisions = lifecycleRevisions
        Task { @MainActor [weak self] in
            guard let self else { return }
            let results = await registry.fetchAll()
            applyResults(results, expectedRevisions: revisions)
        }
    }

    func performFetch(for providerId: String) {
        guard isReadyToFetch(providerId) else { return }
        log("performFetch: provider=\(providerId)")
        switch providerStates[providerId] {
        case .loaded, .error:
            setRefreshing(true, for: providerId)
        default:
            setState(.loading, for: providerId)
            refreshDerived()
        }
        let revision = lifecycleRevisions[providerId, default: 0]
        fetchTasks[providerId]?.cancel()
        fetchTasks[providerId] = Task { @MainActor [weak self] in
            guard let self,
                  let result = await registry.fetchQuota(for: providerId),
                  !Task.isCancelled
            else {
                return
            }
            applyResults([providerId: result], expectedRevisions: [providerId: revision])
            if lifecycleRevisions[providerId, default: 0] == revision {
                fetchTasks[providerId] = nil
            }
        }
    }
}
