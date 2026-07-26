import Core
import Foundation

extension QuotaViewModel {
    func startAutoRefresh(for providerId: String) {
        guard isReadyToFetch(providerId) else { return }
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

    func stopAutoRefresh(for providerId: String) {
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
            startAutoRefresh(for: providerId)
            performFetch(for: providerId)
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
        startAutoRefresh(for: providerId)
        performFetch(for: providerId)
    }

    func invalidateProviderWork(for providerId: String) {
        lifecycleRevisions[providerId, default: 0] += 1
        stopAutoRefresh(for: providerId)
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
