import Core

extension QuotaViewModel {
    func setRefreshing(_ refreshing: Bool, for providerId: String) {
        var copy = isRefreshing
        copy[providerId] = refreshing
        isRefreshing = copy
    }

    func setRefreshError(_ message: String?, for providerId: String) {
        var copy = refreshErrors
        if let message {
            copy[providerId] = message
        } else {
            copy.removeValue(forKey: providerId)
        }
        refreshErrors = copy
    }

    func applyResults(
        _ results: [String: Result<ProviderQuota, Error>],
        expectedRevisions: [String: Int],
        suppressSmartSuccessFor: Set<String>
    ) {
        log("applyResults: got \(results.count) result(s)")
        for (id, result) in results {
            guard expectedRevisions[id, default: 0] == lifecycleRevisions[id, default: 0],
                  isReadyToFetch(id)
            else {
                log("applyResults: provider=\(id) no longer ready, skipping")
                continue
            }
            setRefreshing(false, for: id)

            switch result {
            case let .success(quota):
                log("applyResults: provider=\(id) success, headline=\(quota.headline)")
                setRefreshError(nil, for: id)
                setState(.loaded(quota), for: id)
            case let .failure(error):
                log("applyResults: provider=\(id) failed: \(error.localizedDescription)")
                if error is KeychainError {
                    // Key deleted externally — genuine state change, not a refresh failure.
                    setRefreshError(nil, for: id)
                    setState(.unconfigured, for: id)
                    stopAutoRefresh(for: id)
                } else if case .loaded = providerStates[id] {
                    setRefreshError(error.localizedDescription, for: id)
                } else {
                    setRefreshError(nil, for: id)
                    setState(.error(error.localizedDescription), for: id)
                }
            }

            updateAutomaticRefreshScheduling(
                for: id,
                result: result,
                suppressSmartSuccess: suppressSmartSuccessFor.contains(id)
            )
        }
        refreshDerived()
    }
}
