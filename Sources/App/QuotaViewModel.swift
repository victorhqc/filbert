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

    /// Per-provider state map keyed by provider ID (ui 02 Plan 3).
    ///
    /// Must be assigned as a whole value — dictionary subscript mutation
    /// does not trigger @Observable's setter. Use setState(_:for:) for all
    /// mutations; it also refreshes the derived stored properties.
    private(set) var providerStates: [String: ProviderState] = [:]

    /// Derived: provider IDs with a saved key, sorted by display name (ui 02 AC4).
    private(set) var configuredProviderIds: [String] = []

    /// Derived: whether any provider is configured (ui 02 AC3).
    private(set) var hasAnyConfiguredProvider: Bool = false

    // MARK: - Auto-refresh (AC7: per-provider 5-minute cadence (ui 02))

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
                    // Setup state will be filled by refreshAllSetupStates().
                    setState(.unconfigured, for: info.id)
                }
            }
        }

        refreshDerived()
        fetchAllQuotas()
        refreshAllSetupStates()
    }

    // MARK: - Derived properties — public

    /// All registered provider metadata, sorted by display name (ui 02 AC4).
    var registeredProvidersSorted: [ProviderInfo] {
        registry.registeredProviders.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: - Key management (AC3/AC5: save & clear per provider (ui 02))

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

    // MARK: - Base-URL override (ui 03)

    /// Current override URL for a provider, or `nil` if none is saved (ui 03 Plan 2).
    func overrideURL(for providerId: String) -> URL? {
        ProviderOverrides.baseURL(for: providerId)
    }

    /// Saves a base-URL override for a provider. Throws `ProviderOverrideError`
    /// for non-`https` / empty-host URLs so the view can show an inline error
    /// (ui 03 AC3). When the provider is already configured, triggers an
    /// immediate re-fetch so the user sees the proxy take effect (ui 03 AC4).
    func saveOverrideURL(_ url: URL?, for providerId: String) throws {
        guard !registry.isAPIKeyFree(providerId) else { return }
        try ProviderOverrides.setBaseURL(url, for: providerId)
        log("saveOverrideURL: provider=\(providerId) url=\(url?.absoluteString ?? "nil")")
        if registry.isConfigured(providerId) {
            performFetch(for: providerId)
        }
    }

    // MARK: - Auth shape helpers (ui 05 AC8)

    /// Returns `true` when the provider uses `.apiKeyFree` auth, so the popover
    /// can suppress the "Clear Key" button (ui 05 AC8).
    func isAPIKeyFree(_ providerId: String) -> Bool {
        registry.isAPIKeyFree(providerId)
    }

    /// Returns `true` when the provider's helper can be installed right now
    /// (binary present, helper not yet installed) (ui 05 AC3/AC4).
    func canInstallHelper(for providerId: String) -> Bool {
        registry.canInstallHelper(for: providerId)
    }

    // MARK: - Helper management (ui 05 AC4/AC5)

    /// Installs the provider's helper, updates state to `.loading` during the
    /// operation, and starts auto-refresh + fetch on success (ui 05 AC4).
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

    /// Removes the provider's helper, stops auto-refresh, and re-checks the
    /// setup state (ui 05 AC5).
    func removeHelper(for providerId: String) async {
        log("removeHelper: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await registry.removeHelper(for: providerId)
            log("removeHelper: provider=\(providerId) success")
            stopAutoRefresh(for: providerId)
            // Re-check setup state so the row shows the right post-removal state.
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

    // MARK: - Setup state refresh

    /// Fires `refreshSetupStates()` on the registry and merges the results
    /// into `providerStates` for every `.apiKeyFree` provider (ui 05 AC10).
    private func refreshAllSetupStates() {
        Task {
            let states = await registry.refreshSetupStates()
            for (id, state) in states {
                setState(state, for: id)
            }
            refreshDerived()
        }
    }

    // MARK: - Fetch (AC5: manual refresh (ui 02))

    func fetchQuota(for providerId: String) {
        guard registry.isConfigured(providerId) else {
            log("fetchQuota: provider=\(providerId) not configured, skipping")
            return
        }
        if case .loading = providerStates[providerId] {
            log("fetchQuota: provider=\(providerId) already loading, skipping")
            return
        }
        performFetch(for: providerId)
    }

    /// Manual-refresh entry point bound to the popover's Refresh button
    /// (providers 03 AC3). Runs the provider's proactive refresh (if it
    /// conforms to `ProactiveRefreshable`) before performing the cache read,
    /// so a single click both spawns `claude -p` and re-reads the result.
    ///
    /// Auto-refresh and the initial app-launch fetch still call
    /// `fetchQuota(for:)` directly — scheduling a proactive spawn is
    /// deferred to a separate spec.
    func manualRefresh(for providerId: String) {
        guard registry.isConfigured(providerId) else {
            log("manualRefresh: provider=\(providerId) not configured, skipping")
            return
        }
        if case .loading = providerStates[providerId] {
            log("manualRefresh: provider=\(providerId) already loading, skipping")
            return
        }
        setState(.loading, for: providerId)
        refreshDerived()

        Task { [weak self] in
            await self?.performManualRefresh(providerId: providerId)
        }
    }

    /// Background half of `manualRefresh`. Awaits the proactive refresh
    /// (catching `.notSupported` so non-conforming providers like ZAI fall
    /// through to the standard fetch path) and then runs the fetch.
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
        setState(.loading, for: providerId)
        refreshDerived()

        Task {
            let results = await registry.fetchAll()
            applyResults(results)
        }
    }

    // MARK: - Result processing (AC6: per-provider failure isolation (ui 02))

    private func applyResults(_ results: [String: Result<ProviderQuota, Error>]) {
        log("applyResults: got \(results.count) result(s)")
        for (id, result) in results {
            guard registry.isConfigured(id) else {
                log("applyResults: provider=\(id) no longer configured, skipping")
                continue
            }

            switch result {
            case let .success(quota):
                log("applyResults: provider=\(id) success, headline=\(quota.headline)")
                setState(.loaded(quota), for: id)
            case let .failure(error):
                log("applyResults: provider=\(id) failed: \(error.localizedDescription)")
                if error is KeychainError {
                    setState(.unconfigured, for: id)
                    stopAutoRefresh(for: id)
                } else {
                    setState(.error(error.localizedDescription), for: id)
                }
            }
        }
        refreshDerived()
    }

    // MARK: - Auto-refresh loop (AC7: per-provider 5-minute loop (ui 02))

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

    /// Mutate a single provider's state while triggering @Observable's setter.
    ///
    /// Dictionary subscript mutations only invoke the getter, so the UI would
    /// never see the change. Copy-write-back forces the property setter to fire.
    private func setState(_ state: ProviderState, for providerId: String) {
        var copy = providerStates
        copy[providerId] = state
        providerStates = copy
    }

    /// Recompute stored derived properties from current state.
    private func refreshDerived() {
        let ids = registeredProvidersSorted
            .filter { info in
                guard let state = providerStates[info.id] else { return false }
                switch state {
                case .unconfigured, .setup:
                    return false
                case .loading, .loaded, .error:
                    return true
                }
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
