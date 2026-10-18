import Core
import Foundation

extension QuotaViewModel {
    /// A path can read satisfied from before sleep; the settle delay lets the
    /// monitor report the post-wake state before Filbert trusts it.
    static let wakeNetworkSettleDelay: TimeInterval = 5
    static let wakeNetworkWaitLimit: TimeInterval = 30

    var isNetworkAvailableForAutomaticRefresh: Bool {
        !isAwaitingNetworkAfterWake && networkPath.status == .satisfied
    }

    func isConnectivityRelated(_ error: any Error) -> Bool {
        isConnectivityError(error) || networkPath.status == .unsatisfied
    }

    func installNetworkPathObserver() {
        let changes = networkPath.statusChanges()
        networkPathTask = Task { @MainActor [weak self] in
            for await status in changes {
                guard let self else { return }
                handleNetworkPathChange(status)
            }
        }
    }

    func handleNetworkPathChange(_ status: NetworkPathStatus) {
        guard status == .satisfied else { return }
        if isAwaitingNetworkAfterWake {
            finishWakeNetworkWait()
        } else {
            resumeProvidersAwaitingNetwork()
        }
    }

    func deferAutomaticRefreshUntilNetwork(for providerId: String) {
        providersAwaitingNetwork.insert(providerId)
        startAutoRefresh(for: providerId)
    }

    func resumeProvidersAwaitingNetwork() {
        let waitingIds = providersAwaitingNetwork
        providersAwaitingNetwork.removeAll()
        for providerId in registeredProvidersOrdered.map(\.id) where waitingIds.contains(providerId) {
            guard isEligibleForAutoRefresh(providerId), fetchTasks[providerId] == nil else { continue }
            performFetch(for: providerId, origin: .automatic)
        }
    }

    func handleWakeForRefresh() {
        wakeRevision += 1
        let revision = wakeRevision
        isAwaitingNetworkAfterWake = true
        wakeTask?.cancel()
        wakeTask = Task { @MainActor [weak self] in
            do {
                try await self?.wakeNetworkSleeper(Self.wakeNetworkSettleDelay)
                guard let self, wakeRevision == revision else { return }
                if networkPath.status == .satisfied {
                    finishWakeNetworkWait()
                    return
                }
                try await wakeNetworkSleeper(Self.wakeNetworkWaitLimit - Self.wakeNetworkSettleDelay)
            } catch {
                return
            }
            guard let self, wakeRevision == revision else { return }
            finishWakeNetworkWait()
        }
    }

    func finishWakeNetworkWait() {
        guard isAwaitingNetworkAfterWake else { return }
        isAwaitingNetworkAfterWake = false
        wakeRevision += 1
        wakeTask?.cancel()
        wakeTask = nil

        let deferredIds = providersAwaitingNetwork
        providersAwaitingNetwork.removeAll()
        for providerId in registeredProvidersOrdered.map(\.id) {
            guard isEligibleForAutoRefresh(providerId),
                  fetchTasks[providerId] == nil,
                  deferredIds.contains(providerId) || hasVisibleFailure(providerId)
            else {
                continue
            }
            clearSmartRetryDeadline(for: providerId)
            performFetch(for: providerId, origin: .wake)
        }
    }

    func hasVisibleFailure(_ providerId: String) -> Bool {
        if refreshErrors[providerId] != nil {
            return true
        }
        if case .error = providerStates[providerId] {
            return true
        }
        return false
    }

    func manualRefreshWaitRemaining(for providerId: String) -> TimeInterval? {
        _ = retryGateRevision
        let remaining = providerRetryGateRemaining(for: providerId)
        return remaining > 0 ? remaining : nil
    }

    func scheduleRetryGateExpiry(for providerId: String) {
        retryGateExpiryTasks[providerId]?.cancel()
        retryGateExpiryTasks[providerId] = nil
        retryGateRevision += 1
        let remaining = providerRetryGateRemaining(for: providerId)
        guard remaining > 0 else { return }
        retryGateExpiryTasks[providerId] = Task { @MainActor [weak self] in
            do {
                try await self?.retryGateExpirySleeper(remaining)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            retryGateExpiryTasks[providerId] = nil
            retryGateRevision += 1
        }
    }
}
