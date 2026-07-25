import Core
import Foundation
import Observation

@MainActor
@Observable
final class QuotaViewModel {
    // MARK: - Configuration

    private let keychain: Keychain
    private let registry: ProviderRegistry
    private let refreshInterval: TimeInterval = 300

    // MARK: - State

    /// Must be assigned as a whole value — dictionary subscript mutation
    /// does not trigger @Observable's setter.
    private(set) var providerStates: [String: ProviderState] = [:]

    /// Reassigned as a whole value so @Observable notifies observers —
    /// `ProviderOrder` and `registry` are not observable, so a computed property
    /// would not trigger re-renders.
    private(set) var orderedProviderIds: [String] = []

    private(set) var configuredProviderIds: [String] = []

    private(set) var hasAnyConfiguredProvider: Bool = false

    /// Changing this token tells SwiftUI to re-resolve the UserDefaults-backed
    /// collapse values that live in Core.
    private var collapseStateRevision = 0

    // MARK: - Quiet refresh

    private(set) var isRefreshing: [String: Bool] = [:]

    private(set) var refreshErrors: [String: String] = [:]

    // MARK: - Auto-refresh

    private var refreshLoops: [String: Task<Void, Never>] = [:]

    // MARK: - Init

    init(
        keychain: Keychain = .shared,
        registry: ProviderRegistry
    ) {
        self.keychain = keychain
        self.registry = registry

        for info in registry.registeredProviders {
            let configured = registry.isConfigured(info.id)
            log("init: provider=\(info.id) configured=\(configured)")

            switch info.authShape {
            case .apiKey:
                setState(configured ? .loading : .unconfigured, for: info.id)
                if configured {
                    startAutoRefresh(for: info.id)
                }
            case .apiKeyFree:
                if configured {
                    setState(.loading, for: info.id)
                    startAutoRefresh(for: info.id)
                } else {
                    setState(.unconfigured, for: info.id)
                }
            }
        }

        recomputeOrderedProviderIds()
        refreshDerived()
        fetchAllQuotas()
        refreshAllSetupStates()
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
            guard let state = providerStates[info.id] else { return false }
            return Self.isConfiguredState(state)
        }
    }

    /// Must stay in sync with the states assigned by `init` and `setState(_:for:)`.
    private static func isConfiguredState(_ state: ProviderState) -> Bool {
        switch state {
        case .unconfigured, .setup:
            false
        case .loading, .loaded, .error:
            true
        }
    }

    // MARK: - Key management

    func saveKey(_ key: String, for providerId: String) throws {
        try keychain.save(key, for: providerId)
        log("saveKey: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        startAutoRefresh(for: providerId)
        performFetch(for: providerId)
    }

    func deleteKey(for providerId: String) throws {
        try keychain.delete(for: providerId)
        log("deleteKey: provider=\(providerId)")
        setState(.unconfigured, for: providerId)
        refreshDerived()
        stopAutoRefresh(for: providerId)
    }

    // MARK: - Base-URL override

    func overrideURL(for providerId: String) -> URL? {
        ProviderOverrides.baseURL(for: providerId)
    }

    func saveOverrideURL(_ url: URL?, for providerId: String) throws {
        guard !registry.isAPIKeyFree(providerId) else { return }
        try ProviderOverrides.setBaseURL(url, for: providerId)
        log("saveOverrideURL: provider=\(providerId) url=\(url?.absoluteString ?? "nil")")
        if registry.isConfigured(providerId) {
            performFetch(for: providerId)
        }
    }

    // MARK: - Setup state refresh

    private func refreshAllSetupStates() {
        Task {
            let states = await registry.refreshSetupStates()
            let providers = registry.registeredProviders.filter {
                $0.authShape == .apiKeyFree
            }
            for provider in providers {
                if let state = states[provider.id] {
                    setState(state, for: provider.id)
                    continue
                }
                guard registry.isConfigured(provider.id) else { continue }
                switch providerStates[provider.id] {
                case .loading, .loaded:
                    continue
                default:
                    setState(.loading, for: provider.id)
                    startAutoRefresh(for: provider.id)
                    performFetch(for: provider.id)
                }
            }
            refreshDerived()
        }
    }

    // MARK: - Fetch

    func fetchQuota(for providerId: String) {
        guard registry.isConfigured(providerId) else {
            log("fetchQuota: provider=\(providerId) not configured, skipping")
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
        guard registry.isConfigured(providerId) else {
            log("manualRefresh: provider=\(providerId) not configured, skipping")
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
        Task {
            let results = await registry.fetchAll()
            applyResults(results)
        }
    }

    private func performFetch(for providerId: String) {
        log("performFetch: provider=\(providerId)")
        switch providerStates[providerId] {
        case .loaded, .error:
            setRefreshing(true, for: providerId)
        default:
            setState(.loading, for: providerId)
            refreshDerived()
        }
        Task {
            let results = await registry.fetchAll()
            applyResults(results)
        }
    }

    // MARK: - Auto-refresh loop

    private func startAutoRefresh(for providerId: String) {
        stopAutoRefresh(for: providerId)
        let interval = refreshInterval
        refreshLoops[providerId] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.fetchQuota(for: providerId)
                }
            }
        }
    }

    private func stopAutoRefresh(for providerId: String) {
        refreshLoops[providerId]?.cancel()
        refreshLoops[providerId] = nil
    }

    // MARK: - Helpers

    /// Copy-write-back forces @Observable's setter to fire — dictionary subscript
    /// mutations only invoke the getter, so the UI would never see the change.
    private func setState(_ state: ProviderState, for providerId: String) {
        var copy = providerStates
        copy[providerId] = state
        providerStates = copy
    }

    private func refreshDerived() {
        let byId = Dictionary(
            uniqueKeysWithValues: registry.registeredProviders.map { ($0.id, $0) }
        )
        let ids = orderedProviderIds
            .compactMap { byId[$0] }
            .filter { info in
                guard let state = providerStates[info.id] else { return false }
                return Self.isConfiguredState(state)
            }
            .map(\.id)
        configuredProviderIds = ids
        hasAnyConfiguredProvider = !ids.isEmpty
        log("refreshDerived: configuredProviderIds=\(ids) hasAny=\(hasAnyConfiguredProvider)")
    }

    // MARK: - Diagnostic logging

    private func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[QuotaViewModel] \(message())\n".utf8))
    }
}

// MARK: - Setup actions

extension QuotaViewModel {
    /// Returns `true` when the provider's helper can be installed right now.
    func canInstallHelper(for providerId: String) -> Bool {
        registry.canInstallHelper(for: providerId)
    }

    func credentialImportActionTitle(for providerId: String) -> String? {
        registry.credentialImportActionTitle(for: providerId)
    }

    func installHelper(for providerId: String) async {
        log("installHelper: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await registry.installHelper(for: providerId)
            log("installHelper: provider=\(providerId) success")
            startAutoRefresh(for: providerId)
            performFetch(for: providerId)
        } catch {
            log("installHelper: provider=\(providerId) failed: \(error.localizedDescription)")
            setState(.error(error.localizedDescription), for: providerId)
            refreshDerived()
        }
    }

    func removeHelper(for providerId: String) async {
        log("removeHelper: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await registry.removeHelper(for: providerId)
            log("removeHelper: provider=\(providerId) success")
            stopAutoRefresh(for: providerId)
            let states = await registry.refreshSetupStates()
            if let newState = states[providerId] {
                setState(newState, for: providerId)
            } else {
                setState(.setup(String(localized: "Helper removed")), for: providerId)
            }
        } catch {
            log("removeHelper: provider=\(providerId) failed: \(error.localizedDescription)")
            setState(.error(error.localizedDescription), for: providerId)
        }
        refreshDerived()
    }

    func importCredentials(for providerId: String) async {
        log("importCredentials: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await registry.importCredentials(for: providerId)
            log("importCredentials: provider=\(providerId) success")
            startAutoRefresh(for: providerId)
            performFetch(for: providerId)
        } catch {
            log("importCredentials: provider=\(providerId) failed: \(error.localizedDescription)")
            setState(.error(error.localizedDescription), for: providerId)
            refreshDerived()
        }
    }
}

// MARK: - Provider cards

extension QuotaViewModel {
    func providerInfo(for providerId: String) -> ProviderInfo? {
        registry.registeredProviders.first { $0.id == providerId }
    }

    func isCollapsed(_ providerId: String) -> Bool {
        _ = collapseStateRevision
        return Self.resolvedCollapseState(
            providerId: providerId,
            topProviderId: configuredProviderIds.first,
            savedState: ProviderCollapseState.collapsedState(for: providerId)
        )
    }

    func toggleCollapsed(_ providerId: String) {
        ProviderCollapseState.setCollapsed(!isCollapsed(providerId), for: providerId)
        collapseStateRevision += 1
    }

    static func resolvedCollapseState(
        providerId: String,
        topProviderId: String?,
        savedState: Bool?
    ) -> Bool {
        savedState ?? (providerId != topProviderId)
    }
}

// MARK: - Provider ordering

extension QuotaViewModel {
    func moveProvider(from source: IndexSet, to destination: Int) {
        var ids = orderedProviderIds
        ids.move(fromOffsets: source, toOffset: destination)
        ProviderOrder.setOrder(ids)
        orderedProviderIds = ids
        refreshDerived()
    }

    func persistOrder(_ ids: [String]) {
        ProviderOrder.setOrder(ids)
        orderedProviderIds = ids
        refreshDerived()
    }

    /// Display-name ascending is the App-layer fallback because Core's
    /// `ProviderOrder.effectiveOrder(for:)` is name-agnostic.
    private func recomputeOrderedProviderIds() {
        let sortedByName = registry.registeredProviders.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        orderedProviderIds = ProviderOrder.effectiveOrder(for: sortedByName.map(\.id))
    }
}

// MARK: - Quiet-refresh state mutation + result processing

private extension QuotaViewModel {
    func setRefreshing(_ refreshing: Bool, for providerId: String) {
        var copy = isRefreshing
        copy[providerId] = refreshing
        isRefreshing = copy
    }

    func setRefreshError(_ message: String?, for providerId: String) {
        var copy = refreshErrors
        if let message {
            copy[providerId] = message
        } else {
            copy.removeValue(forKey: providerId)
        }
        refreshErrors = copy
    }

    func applyResults(_ results: [String: Result<ProviderQuota, Error>]) {
        log("applyResults: got \(results.count) result(s)")
        for (id, result) in results {
            guard registry.isConfigured(id) else {
                log("applyResults: provider=\(id) no longer configured, skipping")
                continue
            }
            setRefreshing(false, for: id)

            switch result {
            case let .success(quota):
                log("applyResults: provider=\(id) success, headline=\(quota.headline)")
                setRefreshError(nil, for: id)
                setState(.loaded(quota), for: id)
            case let .failure(error):
                log("applyResults: provider=\(id) failed: \(error.localizedDescription)")
                if error is KeychainError {
                    // Key deleted externally — genuine state change, not a refresh failure.
                    setRefreshError(nil, for: id)
                    setState(.unconfigured, for: id)
                    stopAutoRefresh(for: id)
                } else if case .loaded = providerStates[id] {
                    setRefreshError(error.localizedDescription, for: id)
                } else {
                    setRefreshError(nil, for: id)
                    setState(.error(error.localizedDescription), for: id)
                }
            }
        }
        refreshDerived()
    }
}
