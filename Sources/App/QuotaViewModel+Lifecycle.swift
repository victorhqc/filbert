import Core
import Foundation

extension QuotaViewModel {
    func startAutoRefresh(for providerId: String) {
        guard isEligibleForAutoRefresh(providerId) else {
            stopAutoRefresh(for: providerId)
            return
        }
        stopAutoRefresh(for: providerId)
        let interval = automaticRefreshInterval(for: providerId)
        let schedulingRevision = schedulingRevisions[providerId, default: 0]
        refreshLoops[providerId] = Task { [weak self] in
            do {
                try await self?.autoRefreshSleeper(interval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.performScheduledRefresh(
                for: providerId,
                expectedSchedulingRevision: schedulingRevision
            )
        }
    }

    func stopAutoRefresh(for providerId: String) {
        schedulingRevisions[providerId, default: 0] += 1
        refreshLoops[providerId]?.cancel()
        refreshLoops[providerId] = nil
    }

    func isEnabled(_ providerId: String) -> Bool {
        enabledProviderIds.contains(providerId)
    }

    func setProviderEnabled(_ enabled: Bool, for providerId: String) {
        guard providerInfo(for: providerId) != nil else { return }
        registry.setEnabled(enabled, for: providerId)

        var ids = enabledProviderIds
        if enabled {
            ids.insert(providerId)
        } else {
            ids.remove(providerId)
        }
        enabledProviderIds = ids

        invalidateProviderWork(for: providerId)
        if enabled {
            startEnabledProvider(for: providerId)
        } else if case .loading = providerStates[providerId] {
            setState(.unconfigured, for: providerId)
        }
        refreshDerived()
    }

    func startEnabledProvider(for providerId: String) {
        guard isEnabled(providerId), let info = providerInfo(for: providerId) else { return }

        switch info.authShape {
        case .apiKey:
            guard registry.isConfigured(providerId) else {
                setState(.unconfigured, for: providerId)
                refreshDerived()
                return
            }
            performFetch(for: providerId, origin: .initial)
        case .apiKeyFree:
            let revision = lifecycleRevisions[providerId, default: 0]
            setupTasks[providerId]?.cancel()
            setupTasks[providerId] = Task { @MainActor [weak self] in
                await self?.resolveSetupState(for: providerId, expectedRevision: revision)
            }
        }
    }

    func resolveSetupState(for providerId: String, expectedRevision: Int) async {
        let setupState = await registry.refreshSetupState(for: providerId)
        guard !Task.isCancelled,
              isEnabled(providerId),
              lifecycleRevisions[providerId, default: 0] == expectedRevision
        else {
            return
        }

        if let setupState {
            setState(setupState, for: providerId)
            refreshDerived()
            return
        }

        guard registry.isConfigured(providerId) else {
            setState(.unconfigured, for: providerId)
            refreshDerived()
            return
        }

        setState(.loading, for: providerId)
        refreshDerived()
        performFetch(for: providerId, origin: .initial)
    }

    func invalidateProviderWork(for providerId: String) {
        lifecycleRevisions[providerId, default: 0] += 1
        stopAutoRefresh(for: providerId)
        smartRefreshPolicy.reset(for: providerId)
        syncFastRefreshStatus(for: providerId)
        fetchTasks[providerId]?.cancel()
        fetchTasks[providerId] = nil
        setupTasks[providerId]?.cancel()
        setupTasks[providerId] = nil
        setRefreshing(false, for: providerId)
        setRefreshError(nil, for: providerId)
    }

    func isReadyToFetch(_ providerId: String) -> Bool {
        isEnabled(providerId) && registry.isConfigured(providerId)
    }

    func isEligibleForAutoRefresh(_ providerId: String) -> Bool {
        isReadyToFetch(providerId) && AutoRefreshPreferences.isEnabled(for: providerId)
    }

    func automaticRefreshInterval(for providerId: String) -> TimeInterval {
        guard AutoRefreshPreferences.mode == .smart,
              smartRefreshPolicy.cadence(for: providerId) == .fast
        else {
            return AutoRefreshPreferences.slowInterval
        }
        return AutoRefreshPreferences.fastInterval
    }

    func performScheduledRefresh(
        for providerId: String,
        expectedSchedulingRevision: Int
    ) {
        guard schedulingRevisions[providerId, default: 0] == expectedSchedulingRevision,
              isEligibleForAutoRefresh(providerId),
              fetchTasks[providerId] == nil
        else {
            return
        }
        refreshLoops[providerId] = nil
        performFetch(for: providerId, origin: .automatic)
    }

    func prepareAutomaticRefresh(for providerId: String) {
        guard isEligibleForAutoRefresh(providerId) else {
            stopAutoRefresh(for: providerId)
            return
        }

        if AutoRefreshPreferences.mode == .smart {
            if case let .loaded(quota) = providerStates[providerId] {
                _ = smartRefreshPolicy.recordSuccess(quota, for: providerId)
            }
        }
        if fetchTasks[providerId] == nil {
            startAutoRefresh(for: providerId)
        }
    }

    func establishSmartBaselines() {
        for providerId in registeredProvidersOrdered.map(\.id) {
            guard isEligibleForAutoRefresh(providerId),
                  case let .loaded(quota) = providerStates[providerId]
            else {
                continue
            }
            _ = smartRefreshPolicy.recordSuccess(quota, for: providerId)
        }
    }

    func rescheduleAutomaticRefreshes() {
        for providerId in registeredProvidersOrdered.map(\.id) {
            guard isEligibleForAutoRefresh(providerId) else {
                stopAutoRefresh(for: providerId)
                continue
            }
            guard fetchTasks[providerId] == nil else {
                stopAutoRefresh(for: providerId)
                continue
            }
            startAutoRefresh(for: providerId)
        }
    }

    func recordAutomaticFailure(for providerId: String) {
        guard isEligibleForAutoRefresh(providerId) else { return }
        if AutoRefreshPreferences.mode == .smart {
            _ = smartRefreshPolicy.recordFailure(for: providerId)
            syncFastRefreshStatus(for: providerId)
        }
    }

    func updateAutomaticRefreshScheduling(
        for providerId: String,
        result: Result<ProviderQuota, Error>,
        suppressSmartSuccess: Bool
    ) {
        guard isEligibleForAutoRefresh(providerId) else {
            syncFastRefreshStatus(for: providerId)
            stopAutoRefresh(for: providerId)
            return
        }

        if AutoRefreshPreferences.mode == .smart {
            switch result {
            case let .success(quota):
                if !suppressSmartSuccess {
                    _ = smartRefreshPolicy.recordSuccess(quota, for: providerId)
                }
            case .failure:
                _ = smartRefreshPolicy.recordFailure(for: providerId)
            }
            syncFastRefreshStatus(for: providerId)
        }
        startAutoRefresh(for: providerId)
    }

    func syncFastRefreshStatus(for providerId: String) {
        let shouldShowStatus = AutoRefreshPreferences.mode == .smart
            && isEligibleForAutoRefresh(providerId)
            && smartRefreshPolicy.cadence(for: providerId) == .fast
        setFastRefreshStatusVisible(shouldShowStatus, for: providerId)
    }

    func syncFastRefreshStatuses() {
        for providerId in registeredProvidersOrdered.map(\.id) {
            syncFastRefreshStatus(for: providerId)
        }
    }

    /// Copy-write-back forces @Observable's setter to fire — dictionary subscript
    /// mutations only invoke the getter, so the UI would never see the change.
    func setState(_ state: ProviderState, for providerId: String) {
        var copy = providerStates
        copy[providerId] = state
        providerStates = copy
    }

    func refreshDerived() {
        let byId = Dictionary(
            uniqueKeysWithValues: registry.registeredProviders.map { ($0.id, $0) }
        )
        let ids = orderedProviderIds
            .compactMap { byId[$0] }
            .filter { info in
                isEnabled(info.id) && Self.isConfiguredState(providerStates[info.id])
            }
            .map(\.id)
        configuredProviderIds = ids
        hasAnyConfiguredProvider = !ids.isEmpty
        log("refreshDerived: configuredProviderIds=\(ids) hasAny=\(hasAnyConfiguredProvider)")
    }

    func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[QuotaViewModel] \(message())\n".utf8))
    }
}
