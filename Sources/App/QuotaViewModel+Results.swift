import Core
import Foundation

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
        suppressSmartSuccessFor: Set<String>,
        proactiveRefreshErrors: [String: String] = [:]
    ) {
        for (id, result) in results {
            guard expectedRevisions[id, default: 0] == lifecycleRevisions[id, default: 0],
                  isReadyToFetch(id)
            else {
                continue
            }
            setRefreshing(false, for: id)

            switch result {
            case let .success(quota):
                setRefreshError(proactiveRefreshErrors[id], for: id)
                setState(.loaded(quota), for: id)
                recordActivityObservation(
                    for: id,
                    observation: quota.activityObservation,
                    at: activityRuntime.now()
                )
            case let .failure(error):
                if isCancellationError(error) {
                    if case .loading = providerStates[id], let info = providerInfo(for: id) {
                        setState(.loaded(ProviderQuota(
                            providerId: id,
                            providerName: info.displayName,
                            headline: String(localized: "No data"),
                            lines: [],
                            lastUpdated: Date(),
                            error: String(localized: "Refresh cancelled. Select Refresh to try again.")
                        )), for: id)
                    }
                    continue
                }
                recordError(error, operation: "fetch-quota", providerId: id)
                if isMissingCredentialError(error) {
                    invalidateProviderWork(for: id)
                    setRefreshError(nil, for: id)
                    setState(.unconfigured, for: id)
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
