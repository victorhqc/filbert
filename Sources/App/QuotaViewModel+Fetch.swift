import Core
import Foundation

extension QuotaViewModel {
    func fetchQuota(for providerId: String) {
        performFetch(for: providerId, origin: .initial)
    }

    func manualRefresh(for providerId: String) {
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
                proactiveRefreshErrors: refreshOutcome.errorMessage.map { [providerId: $0] } ?? [:]
            )
            if lifecycleRevisions[providerId, default: 0] == revision {
                fetchTasks[providerId] = nil
            }
        }
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
    ) async -> (suppressSmartSuccess: Bool, errorMessage: String?) {
        guard origin == .automatic || origin == .manual else { return (false, nil) }

        do {
            try await registry.proactiveRefresh(for: providerId)
            return (false, nil)
        } catch ProviderSetupError.notSupported {
            return (false, nil)
        } catch where isCancellationError(error) {
            return (false, nil)
        } catch {
            guard !Task.isCancelled,
                  lifecycleRevisions[providerId, default: 0] == expectedRevision
            else {
                return (false, nil)
            }
            guard !isMissingCredentialError(error) else { return (false, nil) }
            recordError(error, operation: "proactive-refresh", providerId: providerId)
            if origin == .automatic {
                recordAutomaticFailure(for: providerId)
            }
            return (true, error.localizedDescription)
        }
    }
}
