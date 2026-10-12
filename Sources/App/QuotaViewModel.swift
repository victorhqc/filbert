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
    let errorLog: ErrorLog
    let autoRefreshSleeper: @Sendable (TimeInterval) async throws -> Void
    let smartRefreshElapsed: @Sendable () -> TimeInterval
    let smartRefreshBoundarySleeper: @Sendable (TimeInterval) async throws -> Void

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

    var isAutomaticMenuBarProviderSelection = MenuBarProviderSelectionPreferences.isAutomatic

    var isVintageMacIconEnabled = VintageMacIcon.isEnabled

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

    var smartRefreshBoundaryTasks: [String: Task<Void, Never>] = [:]

    var smartRefreshBoundaryRevisions: [String: Int] = [:]

    var smartRefreshNotBefore: [String: TimeInterval] = [:]

    var smartExtensionRevision = 0

    var activityRuntime: MenuBarProviderActivityRuntime

    var autoRefreshSettingsRevision = 0

    // MARK: - Allowance forecasting

    var allowanceForecaster = AllowanceForecaster()

    var systemClockObserverToken: NSObjectProtocol?

    // MARK: - Init

    init(
        keychain: Keychain = .shared,
        registry: ProviderRegistry,
        errorLog: ErrorLog? = nil,
        autoRefreshSleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(for: .seconds(interval))
        },
        smartRefreshBoundarySleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(for: .seconds(interval))
        },
        smartRefreshElapsed: @escaping @Sendable () -> TimeInterval = {
            let clock = MonotonicElapsedClock()
            return { clock.elapsed() }
        }(),
        activityExpirationSleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(for: .seconds(interval))
        },
        activityNow: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychain = keychain
        self.registry = registry
        self.errorLog = errorLog ?? registry.errorLog
        self.autoRefreshSleeper = autoRefreshSleeper
        self.smartRefreshBoundarySleeper = smartRefreshBoundarySleeper
        self.smartRefreshElapsed = smartRefreshElapsed
        activityRuntime = MenuBarProviderActivityRuntime(
            expirationSleeper: activityExpirationSleeper,
            now: activityNow
        )

        installActivityLifecycleObservers()
        installSystemClockObserver()

        var enabledIds: Set<String> = []
        for info in registry.registeredProviders {
            guard registry.isEnabled(info.id) else {
                setState(.unconfigured, for: info.id)
                continue
            }
            enabledIds.insert(info.id)

            let configured = registry.isConfigured(info.id)
            if let message = registry.configurationError(for: info.id) {
                setState(.error(message), for: info.id)
            } else {
                setState(configured ? .loading : .unconfigured, for: info.id)
            }
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

    var autoRefreshQuietWindow: TimeInterval {
        _ = autoRefreshSettingsRevision
        return AutoRefreshPreferences.quietWindow
    }

    var autoRefreshCooldownInterval: TimeInterval {
        _ = autoRefreshSettingsRevision
        return SmartRefreshPolicy.cooldownInterval(
            slowInterval: AutoRefreshPreferences.slowInterval,
            fastInterval: AutoRefreshPreferences.fastInterval
        )
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

        let date = activityRuntime.now()
        _ = activityRuntime.policy.recordFastRefreshState(visible, for: providerId, at: date)

        var providerIds = fastRefreshingProviderIds
        if visible {
            providerIds.insert(providerId)
        } else {
            providerIds.remove(providerId)
        }
        fastRefreshingProviderIds = providerIds
        refreshActivitySelection(at: date)
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
        smartRefreshNotBefore.removeAll()
        smartExtensionRevision += 1
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

    func setAutoRefreshQuietWindow(_ interval: TimeInterval) {
        let supportedInterval = AutoRefreshPreferences.supportedQuietWindow(interval)
        guard AutoRefreshPreferences.quietWindow != supportedInterval else { return }
        AutoRefreshPreferences.quietWindow = supportedInterval
        autoRefreshSettingsRevision += 1
        syncFastRefreshStatuses()
        rescheduleAutomaticRefreshes()
    }

    // MARK: - Key management

    func saveKey(_ key: String, for providerId: String) throws {
        do {
            try keychain.save(key, for: providerId)
        } catch {
            recordError(error, operation: "save-key", providerId: providerId)
            throw error
        }
        setProviderEnabled(true, for: providerId)
    }

    func deleteKey(for providerId: String) throws {
        do {
            try keychain.delete(for: providerId)
        } catch {
            recordError(error, operation: "delete-key", providerId: providerId)
            throw error
        }
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
        do {
            try ProviderOverrides.setBaseURL(url, for: providerId)
        } catch {
            recordError(error, operation: "save-override", providerId: providerId)
            throw error
        }
        clearAllowanceForecasts(for: providerId)
        if isEnabled(providerId), registry.isConfigured(providerId) {
            performFetch(for: providerId)
        }
    }
}
