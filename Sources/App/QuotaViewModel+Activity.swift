import AppKit
import Core
import Foundation

struct MenuBarProviderActivityRuntime {
    var policy = MenuBarProviderActivityPolicy()
    var selectionDate: Date
    var selectionRevision = 0
    var expirationTask: Task<Void, Never>?
    var expirationRevision = 0
    var lifecycleObserverTokens: [NSObjectProtocol] = []
    let expirationSleeper: @Sendable (TimeInterval) async throws -> Void
    let now: @Sendable () -> Date

    init(
        expirationSleeper: @escaping @Sendable (TimeInterval) async throws -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.expirationSleeper = expirationSleeper
        self.now = now
        selectionDate = now()
    }
}

extension QuotaViewModel {
    var effectiveActivityScores: [String: Double] {
        _ = activityRuntime.selectionRevision
        return activityRuntime.policy.effectiveScores(at: activityRuntime.selectionDate)
    }

    func recordActivityObservation(
        for providerId: String,
        observation: ProviderActivityObservation?,
        at date: Date
    ) {
        _ = activityRuntime.policy.recordSuccessfulResult(
            for: providerId,
            observation: observation,
            at: date
        )
        refreshActivitySelection(at: date)
    }

    func refreshActivitySelection(at date: Date) {
        activityRuntime.selectionDate = date
        activityRuntime.selectionRevision += 1
        rescheduleActivityExpiration(at: date)
    }

    func rescheduleActivityExpiration() {
        refreshActivitySelection(at: activityRuntime.now())
    }

    func handleActivityWillSleep() {
        cancelActivityExpiration()
    }

    func handleActivityDidWake() {
        refreshActivitySelection(at: activityRuntime.now())
    }

    func installActivityLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        activityRuntime.lifecycleObserverTokens.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleActivityWillSleep()
                }
            }
        )
        activityRuntime.lifecycleObserverTokens.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleActivityDidWake()
                }
            }
        )
    }

    func resetActivityForInvalidProviders(registeredProviderIds: Set<String>) {
        let trackedProviderIds = activityRuntime.policy.baselineProviderIds
            .union(activityRuntime.policy.activeScoreProviderIds)
            .union(fastRefreshingProviderIds)
        for providerId in trackedProviderIds {
            guard registeredProviderIds.contains(providerId),
                  enabledProviderIds.contains(providerId),
                  Self.isConfiguredState(providerStates[providerId])
            else {
                activityRuntime.policy.reset(for: providerId)
                if fastRefreshingProviderIds.contains(providerId) {
                    setFastRefreshStatusVisible(false, for: providerId)
                }
                continue
            }
        }
    }
}

private extension QuotaViewModel {
    func cancelActivityExpiration() {
        activityRuntime.expirationRevision += 1
        activityRuntime.expirationTask?.cancel()
        activityRuntime.expirationTask = nil
    }

    func rescheduleActivityExpiration(at date: Date) {
        cancelActivityExpiration()
        _ = activityRuntime.policy.resolve(at: date)

        guard isAutomaticMenuBarProviderSelection,
              let providerId = MenuBarProviderSelector.providerId(
                  configuredProviderIds: configuredProviderIds,
                  enabledProviderIds: enabledProviderIds,
                  providerStates: providerStates,
                  effectiveActivityScores: activityRuntime.policy.effectiveScores(at: date),
                  isAutomatic: true
              ),
              let expirationDate = activityRuntime.policy.expirationDate(
                  for: providerId,
                  at: date
              )
        else {
            return
        }

        let interval = max(0, expirationDate.timeIntervalSince(date))
        let revision = activityRuntime.expirationRevision
        let sleeper = activityRuntime.expirationSleeper
        activityRuntime.expirationTask = Task { @MainActor [weak self] in
            do {
                try await sleeper(interval)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  activityRuntime.expirationRevision == revision
            else {
                return
            }
            activityRuntime.expirationTask = nil
            refreshActivitySelection(at: activityRuntime.now())
        }
    }
}
