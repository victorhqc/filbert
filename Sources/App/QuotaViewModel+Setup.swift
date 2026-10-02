import Core

extension QuotaViewModel {
    /// Returns `true` when the provider's helper can be installed right now.
    func canInstallHelper(for providerId: String) -> Bool {
        guard isEnabled(providerId) else { return false }
        return registry.canInstallHelper(for: providerId)
    }

    func canRemoveHelper(for providerId: String) -> Bool {
        guard isEnabled(providerId) else { return false }
        return registry.canRemoveHelper(for: providerId)
    }

    func credentialImportActionTitle(for providerId: String) -> String? {
        guard isEnabled(providerId) else { return nil }
        return registry.credentialImportActionTitle(for: providerId)
    }

    func installHelper(for providerId: String) async {
        await performSetupOperation(for: providerId, operation: "install-helper") {
            try await registry.installHelper(for: providerId)
        }
    }

    func removeHelper(for providerId: String) async {
        await performSetupOperation(for: providerId, operation: "remove-helper") {
            try await registry.removeHelper(for: providerId)
        }
    }

    func importCredentials(for providerId: String) async {
        await performSetupOperation(for: providerId, operation: "import-credentials") {
            try await registry.importCredentials(for: providerId)
        }
    }

    private func performSetupOperation(
        for providerId: String,
        operation: String,
        action: () async throws -> Void
    ) async {
        guard isEnabled(providerId) else { return }
        let previousState = providerStates[providerId] ?? .unconfigured
        invalidateProviderWork(for: providerId)
        let revision = lifecycleRevisions[providerId, default: 0]
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await action()
        } catch {
            guard isEnabled(providerId),
                  lifecycleRevisions[providerId, default: 0] == revision
            else { return }
            if isCancellationError(error) || error as? ProviderSetupError == .notSupported || Task.isCancelled {
                restoreStateAfterCancellation(previousState, for: providerId)
            } else if isMissingCredentialError(error) {
                setState(
                    .setup(String(localized: "No credentials found. Sign in to this provider and try again.")),
                    for: providerId
                )
            } else {
                recordError(error, operation: operation, providerId: providerId)
                setState(.error(error.localizedDescription), for: providerId)
            }
            refreshDerived()
            return
        }
        guard isEnabled(providerId),
              lifecycleRevisions[providerId, default: 0] == revision
        else { return }
        if Task.isCancelled {
            restoreStateAfterCancellation(previousState, for: providerId)
        } else {
            startEnabledProvider(for: providerId)
        }
        refreshDerived()
    }

    private func restoreStateAfterCancellation(_ state: ProviderState, for providerId: String) {
        if case .loading = state {
            startEnabledProvider(for: providerId)
        } else {
            setState(state, for: providerId)
            startAutoRefresh(for: providerId)
        }
    }
}
