import Core

extension QuotaViewModel {
    /// Returns `true` when the provider's helper can be installed right now.
    func canInstallHelper(for providerId: String) -> Bool {
        guard isEnabled(providerId) else { return false }
        return registry.canInstallHelper(for: providerId)
    }

    func credentialImportActionTitle(for providerId: String) -> String? {
        guard isEnabled(providerId) else { return nil }
        return registry.credentialImportActionTitle(for: providerId)
    }

    func installHelper(for providerId: String) async {
        guard isEnabled(providerId) else { return }
        log("installHelper: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await registry.installHelper(for: providerId)
            log("installHelper: provider=\(providerId) success")
            startEnabledProvider(for: providerId)
        } catch {
            log("installHelper: provider=\(providerId) failed: \(error.localizedDescription)")
            setState(.error(error.localizedDescription), for: providerId)
            refreshDerived()
        }
    }

    func removeHelper(for providerId: String) async {
        guard isEnabled(providerId) else { return }
        log("removeHelper: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await registry.removeHelper(for: providerId)
            log("removeHelper: provider=\(providerId) success")
            invalidateProviderWork(for: providerId)
            startEnabledProvider(for: providerId)
        } catch {
            log("removeHelper: provider=\(providerId) failed: \(error.localizedDescription)")
            setState(.error(error.localizedDescription), for: providerId)
        }
        refreshDerived()
    }

    func importCredentials(for providerId: String) async {
        guard isEnabled(providerId) else { return }
        log("importCredentials: provider=\(providerId)")
        setState(.loading, for: providerId)
        refreshDerived()
        do {
            try await registry.importCredentials(for: providerId)
            log("importCredentials: provider=\(providerId) success")
            startEnabledProvider(for: providerId)
        } catch {
            log("importCredentials: provider=\(providerId) failed: \(error.localizedDescription)")
            setState(.error(error.localizedDescription), for: providerId)
            refreshDerived()
        }
    }
}
