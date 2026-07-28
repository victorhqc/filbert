import Core
import Foundation
import Observation

enum RefreshOrigin: Equatable {
    case initial
    case manual
    case automatic
}

@MainActor
@Observable
final class QuotaViewModel {
    // MARK: - Configuration

    private let keychain: Keychain
    let registry: ProviderRegistry
    let autoRefreshSleeper: @Sendable (TimeInterval) async throws -> Void

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

    var schedulingRevisions: [String: Int] = [:]

    var smartRefreshPolicy = SmartRefreshPolicy()

    private(set) var fastRefreshingProviderIds: Set<String> = []

    var autoRefreshSettingsRevision = 0

    // MARK: - Init

    init(
        keychain: Keychain = .shared,
        registry: ProviderRegistry,
        autoRefreshSleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(for: .seconds(interval))
        }
    ) {
        self.keychain = keychain
        self.registry = registry
        self.autoRefreshSleeper = autoRefreshSleeper

        var enabledIds: Set<String> = []
        for info in registry.registeredProviders {
            guard registry.isEnabled(info.id) else {
                setState(.unconfigured, for: info.id)
                continue
            }
            enabledIds.insert(info.id)

            let configured = registry.isConfigured(info.id)
            log("init: provider=\(info.id) configured=\(configured)")
            setState(configured ? .loading : .unconfigured, for: info.id)
        }
        enabledProviderIds = enabledIds

        recomputeOrderedProviderIds()
        refreshDerived()
        for info in registry.registeredProviders where enabledIds.contains(info.id) {
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

    var autoRefreshMode: AutoRefreshMode {
        _ = autoRefreshSettingsRevision
        return AutoRefreshPreferences.mode
    }

    var autoRefreshSlowInterval: TimeInterval {
        _ = autoRefreshSettingsRevision
        return AutoRefreshPreferences.slowInterval
    }

    var autoRefreshFastInterval: TimeInterval {
        _ = autoRefreshSettingsRevision
        return AutoRefreshPreferences.fastInterval
    }

    func isAutoRefreshEnabled(for providerId: String) -> Bool {
        _ = autoRefreshSettingsRevision
        return AutoRefreshPreferences.isEnabled(for: providerId)
    }

    func isFastAutomaticRefreshActive(for providerId: String) -> Bool {
        fastRefreshingProviderIds.contains(providerId)
    }

    func setFastRefreshStatusVisible(_ visible: Bool, for providerId: String) {
        guard fastRefreshingProviderIds.contains(providerId) != visible else { return }

        var providerIds = fastRefreshingProviderIds
        if visible {
            providerIds.insert(providerId)
        } else {
            providerIds.remove(providerId)
        }
        fastRefreshingProviderIds = providerIds
    }

    func setAutoRefreshEnabled(_ enabled: Bool, for providerId: String) {
        guard providerInfo(for: providerId) != nil else { return }
        AutoRefreshPreferences.setEnabled(enabled, for: providerId)
        autoRefreshSettingsRevision += 1

        guard enabled else {
            smartRefreshPolicy.reset(for: providerId)
            syncFastRefreshStatus(for: providerId)
            stopAutoRefresh(for: providerId)
            return
        }

        prepareAutomaticRefresh(for: providerId)
    }

    func setAutoRefreshMode(_ mode: AutoRefreshMode) {
        guard AutoRefreshPreferences.mode != mode else { return }
        AutoRefreshPreferences.mode = mode
        smartRefreshPolicy.resetAll()
        syncFastRefreshStatuses()
        autoRefreshSettingsRevision += 1

        if mode == .smart {
            establishSmartBaselines()
        }
        rescheduleAutomaticRefreshes()
    }

    func setAutoRefreshSlowInterval(_ interval: TimeInterval) {
        let supportedInterval = AutoRefreshPreferences.supportedSlowInterval(interval)
        guard AutoRefreshPreferences.slowInterval != supportedInterval else { return }
        AutoRefreshPreferences.slowInterval = supportedInterval
        autoRefreshSettingsRevision += 1
        rescheduleAutomaticRefreshes()
    }

    func setAutoRefreshFastInterval(_ interval: TimeInterval) {
        let supportedInterval = AutoRefreshPreferences.supportedFastInterval(interval)
        guard AutoRefreshPreferences.fastInterval != supportedInterval else { return }
        AutoRefreshPreferences.fastInterval = supportedInterval
        autoRefreshSettingsRevision += 1
        rescheduleAutomaticRefreshes()
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
        performFetch(for: providerId, origin: .initial)
    }

    func manualRefresh(for providerId: String) {
        performFetch(for: providerId, origin: .manual)
    }

    func fetchAllQuotas() {
        for providerId in registeredProvidersOrdered.map(\.id) {
            fetchQuota(for: providerId)
        }
    }

    func performFetch(for providerId: String, origin: RefreshOrigin = .initial) {
        guard isReadyToFetch(providerId), fetchTasks[providerId] == nil else { return }
        log("performFetch: provider=\(providerId)")
        switch providerStates[providerId] {
        case .loaded, .error:
            setRefreshing(true, for: providerId)
        default:
            setState(.loading, for: providerId)
            refreshDerived()
        }
        let revision = lifecycleRevisions[providerId, default: 0]
        fetchTasks[providerId] = Task { @MainActor [weak self] in
            guard let self else { return }
            let suppressSmartSuccess = await proactiveRefreshIfNeeded(
                for: providerId,
                origin: origin,
                expectedRevision: revision
            )
            guard let result = await registry.fetchQuota(for: providerId) else {
                if lifecycleRevisions[providerId, default: 0] == revision {
                    fetchTasks[providerId] = nil
                    if !isReadyToFetch(providerId) {
                        setRefreshing(false, for: providerId)
                        setState(.unconfigured, for: providerId)
                        refreshDerived()
                    }
                }
                return
            }
            guard !Task.isCancelled else {
                return
            }
            applyResults(
                [providerId: result],
                expectedRevisions: [providerId: revision],
                suppressSmartSuccessFor: suppressSmartSuccess ? [providerId] : []
            )
            if lifecycleRevisions[providerId, default: 0] == revision {
                fetchTasks[providerId] = nil
            }
        }
    }

    private func proactiveRefreshIfNeeded(
        for providerId: String,
        origin: RefreshOrigin,
        expectedRevision: Int
    ) async -> Bool {
        guard origin == .automatic || origin == .manual else { return false }

        do {
            try await registry.proactiveRefresh(for: providerId)
            log("proactiveRefresh: provider=\(providerId) ok")
            return false
        } catch ProviderSetupError.notSupported {
            return false
        } catch {
            log("proactiveRefresh: provider=\(providerId) failed: \(error.localizedDescription)")
            guard origin == .automatic,
                  lifecycleRevisions[providerId, default: 0] == expectedRevision
            else {
                return false
            }
            recordAutomaticFailure(for: providerId)
            return true
        }
    }
}
