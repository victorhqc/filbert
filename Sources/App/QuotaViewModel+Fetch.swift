import Core
import Foundation

private struct ProactiveRefreshOutcome {
    var suppressSmartSuccess = false
    var errorMessage: DisplayText?
    var isConnectivityFailure = false
}

extension QuotaViewModel {
    func fetchQuota(for providerId: String) {
        performFetch(for: providerId, origin: .initial)
    }

    func manualRefresh(for providerId: String) {
        guard !isWithinProviderRetryGate(providerId) else { return }
        recordManualActivityHint(for: providerId)
        performFetch(for: providerId, origin: .manual)
    }

    func fetchAllQuotas() {
        for providerId in registeredProvidersOrdered.map(\.id) {
            fetchQuota(for: providerId)
        }
    }

    func performFetch(for providerId: String, origin: RefreshOrigin = .initial) {
        guard isEnabled(providerId), fetchTasks[providerId] == nil else { return }
        guard isReadyToFetch(providerId) else {
            applyConfigurationError(for: providerId)
            return
        }
        guard admitsFetch(for: providerId, origin: origin) else { return }
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
            let refreshOutcome = await proactiveRefreshIfNeeded(
                for: providerId,
                origin: origin,
                expectedRevision: revision
            )
            guard let result = await registry.fetchQuota(for: providerId) else {
                finishUnavailableFetch(for: providerId, expectedRevision: revision)
                return
            }
            guard !Task.isCancelled else { return }
            applyResults(
                [providerId: result],
                expectedRevisions: [providerId: revision],
                suppressSmartSuccessFor: refreshOutcome.suppressSmartSuccess ? [providerId] : [],
                proactiveRefreshErrors: refreshOutcome.errorMessage.map { [providerId: $0] } ?? [:],
                proactiveConnectivityFailures: refreshOutcome.isConnectivityFailure ? [providerId] : [],
                origin: origin
            )
            scheduleRetryGateExpiry(for: providerId)
            if lifecycleRevisions[providerId, default: 0] == revision {
                fetchTasks[providerId] = nil
            }
        }
    }

    /// A provider retry gate blocks every origin. The failure hold blocks all
    /// but a manual refresh. A blocked request reschedules the automatic loop
    /// so a hold cannot stall it.
    private func admitsFetch(for providerId: String, origin: RefreshOrigin) -> Bool {
        guard !isWithinProviderRetryGate(providerId),
              origin == .manual || !isWithinFailureHold(providerId)
        else {
            if isEligibleForAutoRefresh(providerId) {
                startAutoRefresh(for: providerId)
            }
            return false
        }
        if origin.isAutomatic, !isNetworkAvailableForAutomaticRefresh {
            deferAutomaticRefreshUntilNetwork(for: providerId)
            return false
        }
        return true
    }

    private func finishUnavailableFetch(for providerId: String, expectedRevision: Int) {
        guard lifecycleRevisions[providerId, default: 0] == expectedRevision else { return }
        fetchTasks[providerId] = nil
        setRefreshing(false, for: providerId)
        guard !isReadyToFetch(providerId) else { return }
        if registry.configurationError(for: providerId) != nil {
            applyConfigurationError(for: providerId)
        } else {
            setState(.unconfigured, for: providerId)
        }
        refreshDerived()
    }

    private func applyConfigurationError(for providerId: String) {
        guard let message = registry.configurationError(for: providerId) else { return }
        if case .loaded = providerStates[providerId] {
            setRefreshError(message, for: providerId)
        } else {
            setState(.error(message), for: providerId)
        }
        refreshDerived()
    }

    private func proactiveRefreshIfNeeded(
        for providerId: String,
        origin: RefreshOrigin,
        expectedRevision: Int
    ) async -> ProactiveRefreshOutcome {
        guard origin != .initial else { return ProactiveRefreshOutcome() }

        do {
            try await registry.proactiveRefresh(for: providerId)
            return ProactiveRefreshOutcome()
        } catch ProviderSetupError.notSupported {
            return ProactiveRefreshOutcome()
        } catch where isCancellationError(error) {
            return ProactiveRefreshOutcome()
        } catch {
            guard !Task.isCancelled,
                  lifecycleRevisions[providerId, default: 0] == expectedRevision
            else {
                return ProactiveRefreshOutcome()
            }
            guard !isMissingCredentialError(error) else { return ProactiveRefreshOutcome() }
            recordError(error, operation: "proactive-refresh", providerId: providerId, origin: origin)
            let isConnectivityFailure = isConnectivityRelated(error)
            if origin.isAutomatic {
                recordAutomaticFailure(for: providerId, isConnectivityFailure: isConnectivityFailure)
            }
            return ProactiveRefreshOutcome(
                suppressSmartSuccess: true,
                errorMessage: DisplayText(describing: error),
                isConnectivityFailure: isConnectivityFailure
            )
        }
    }
}
