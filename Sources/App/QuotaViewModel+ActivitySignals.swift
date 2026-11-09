import Core
import Foundation

extension QuotaViewModel {
    /// Subscribes in every refresh mode; `recordActivitySignal` drops the
    /// signals that cannot apply.
    func syncActivitySignalSubscription(for providerId: String) {
        guard isReadyToFetch(providerId),
              Self.isConfiguredState(providerStates[providerId])
        else {
            cancelActivitySignalSubscription(for: providerId)
            return
        }
        guard activitySignalTasks[providerId] == nil,
              let signals = registry.activitySignals(for: providerId)
        else {
            return
        }

        activitySignalTasks[providerId] = Task { @MainActor [weak self] in
            for await _ in signals {
                guard !Task.isCancelled else { return }
                self?.recordActivitySignal(for: providerId)
            }
            // A cancelled task has already been replaced or removed; only a
            // stream the provider finished may clear its own entry.
            guard !Task.isCancelled, let self else { return }
            activitySignalTasks[providerId] = nil
        }
    }

    func cancelActivitySignalSubscription(for providerId: String) {
        activitySignalTasks[providerId]?.cancel()
        activitySignalTasks[providerId] = nil
    }

    func recordActivitySignal(for providerId: String) {
        guard AutoRefreshPreferences.mode == .smart,
              Self.isConfiguredState(providerStates[providerId]),
              isEligibleForAutoRefresh(providerId)
        else {
            return
        }
        recordSmartActivityHint(for: providerId)
        pullAutomaticRefreshForward(for: providerId)
    }

    /// `automaticRefreshInterval` already folds in the minimum interval, the
    /// retry gate, and the failure hold, so the earlier deadline can never
    /// break a safety limit.
    private func pullAutomaticRefreshForward(for providerId: String) {
        guard fetchTasks[providerId] == nil else { return }
        let candidate = smartRefreshElapsed() + automaticRefreshInterval(for: providerId)
        if let deadline = refreshLoops[providerId]?.deadline, deadline <= candidate {
            return
        }
        startAutoRefresh(for: providerId)
    }
}
