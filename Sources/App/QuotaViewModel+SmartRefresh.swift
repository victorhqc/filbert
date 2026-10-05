import Core
import Foundation

extension QuotaViewModel {
    func canInvokeInference(for providerId: String) -> Bool {
        providerRefreshCharacteristics(for: providerId).canInvokeInference
    }

    func providerRefreshCharacteristics(for providerId: String) -> ProviderRefreshCharacteristics {
        providerInfo(for: providerId)?.refreshCharacteristics ?? ProviderRefreshCharacteristics()
    }

    func automaticRefreshInterval(for providerId: String) -> TimeInterval {
        var interval = baseAutomaticRefreshInterval(for: providerId)
        if let minimum = providerRefreshCharacteristics(for: providerId).minimumInterval {
            interval = max(interval, minimum)
        }
        if let notBefore = smartRefreshNotBefore[providerId] {
            interval = max(interval, notBefore - smartRefreshElapsed())
        }
        return max(0, interval)
    }

    func recordManualActivityHint(for providerId: String) {
        guard AutoRefreshPreferences.mode == .smart,
              isEligibleForAutoRefresh(providerId)
        else {
            return
        }
        _ = smartRefreshPolicy.recordActivityHint(
            for: providerId,
            at: smartRefreshElapsed(),
            quietWindow: AutoRefreshPreferences.quietWindow,
            canInvokeInference: canInvokeInference(for: providerId)
        )
        syncFastRefreshStatus(for: providerId)
    }

    func startSmartExtension(for providerId: String, duration: TimeInterval) {
        guard AutoRefreshPreferences.mode == .smart,
              isEligibleForAutoRefresh(providerId)
        else {
            return
        }
        smartRefreshPolicy.recordExtension(
            for: providerId,
            duration: duration,
            at: smartRefreshElapsed()
        )
        smartExtensionRevision += 1
        syncFastRefreshStatus(for: providerId)

        guard fetchTasks[providerId] == nil else { return }
        if isWithinSmartSafetyDeadline(providerId) {
            startAutoRefresh(for: providerId)
        } else {
            performFetch(for: providerId, origin: .automatic)
        }
    }

    func stopSmartExtension(for providerId: String) {
        guard smartRefreshPolicy.extensionDeadline(for: providerId) != nil else { return }
        smartRefreshPolicy.stopExtension(for: providerId)
        smartExtensionRevision += 1
        syncFastRefreshStatus(for: providerId)
        if fetchTasks[providerId] == nil {
            startAutoRefresh(for: providerId)
        }
    }

    func smartExtensionRemaining(for providerId: String) -> TimeInterval? {
        _ = smartExtensionRevision
        guard let deadline = smartRefreshPolicy.extensionDeadline(for: providerId) else { return nil }
        return max(0, deadline - smartRefreshElapsed())
    }

    func recordSmartFailure(for providerId: String) {
        guard AutoRefreshPreferences.mode == .smart else { return }
        _ = smartRefreshPolicy.recordFailure(for: providerId)
        let slowInterval = AutoRefreshPreferences.slowInterval
        let retryDeadline = providerRefreshCharacteristics(for: providerId).retryDeadline ?? 0
        smartRefreshNotBefore[providerId] = smartRefreshElapsed() + max(slowInterval, retryDeadline)
        smartExtensionRevision += 1
    }

    func clearSmartRetryDeadline(for providerId: String) {
        smartRefreshNotBefore.removeValue(forKey: providerId)
    }

    func isWithinSmartSafetyDeadline(_ providerId: String) -> Bool {
        guard let notBefore = smartRefreshNotBefore[providerId] else { return false }
        return smartRefreshElapsed() < notBefore
    }

    private func baseAutomaticRefreshInterval(for providerId: String) -> TimeInterval {
        guard AutoRefreshPreferences.mode == .smart else {
            return AutoRefreshPreferences.slowInterval
        }
        let slowInterval = AutoRefreshPreferences.slowInterval
        let fastInterval = AutoRefreshPreferences.fastInterval
        switch smartRefreshCadence(for: providerId) {
        case .slow:
            return slowInterval
        case .fast:
            return fastInterval
        case .cooldown:
            return SmartRefreshPolicy.cooldownInterval(
                slowInterval: slowInterval,
                fastInterval: fastInterval
            )
        }
    }

    func effectiveFastInterval(for providerId: String) -> TimeInterval {
        let fastInterval = AutoRefreshPreferences.fastInterval
        guard let minimum = providerRefreshCharacteristics(for: providerId).minimumInterval else {
            return fastInterval
        }
        return max(fastInterval, minimum)
    }

    func providerMinimumIntervalOverridesFastRefresh(for providerId: String) -> Bool {
        let minimum = providerRefreshCharacteristics(for: providerId).minimumInterval ?? 0
        return minimum > AutoRefreshPreferences.fastInterval
    }
}
