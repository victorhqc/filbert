import Core
import Foundation

extension QuotaViewModel {
    func setRefreshing(_ refreshing: Bool, for providerId: String) {
        var copy = isRefreshing
        copy[providerId] = refreshing
        isRefreshing = copy
    }

    func setRefreshError(_ message: DisplayText?, for providerId: String) {
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
        proactiveRefreshErrors: [String: DisplayText] = [:],
        proactiveConnectivityFailures: Set<String> = [],
        origin: RefreshOrigin = .initial
    ) {
        for (id, result) in results {
            guard expectedRevisions[id, default: 0] == lifecycleRevisions[id, default: 0],
                  isReadyToFetch(id)
            else {
                continue
            }
            setRefreshing(false, for: id)
            var isConnectivityFailure = proactiveConnectivityFailures.contains(id)

            switch result {
            case let .success(quota):
                setRefreshError(proactiveRefreshErrors[id], for: id)
                setState(.loaded(quota), for: id)
                recordAllowanceObservation(from: quota, for: id, at: activityRuntime.now())
                recordActivityObservation(
                    for: id,
                    observation: quota.activityObservation,
                    at: activityRuntime.now()
                )
            case let .failure(error):
                if isCancellationError(error) {
                    applyCancelledFetch(for: id)
                    continue
                }
                recordError(error, operation: "fetch-quota", providerId: id, origin: origin)
                isConnectivityFailure = isConnectivityRelated(error)
                if isMissingCredentialError(error) {
                    invalidateProviderWork(for: id)
                    setRefreshError(nil, for: id)
                    setState(.unconfigured, for: id)
                } else if case .loaded = providerStates[id] {
                    setRefreshError(DisplayText(describing: error), for: id)
                } else {
                    setRefreshError(nil, for: id)
                    setState(.error(DisplayText(describing: error)), for: id)
                }
            }

            updateAutomaticRefreshScheduling(
                for: id,
                result: result,
                suppressSmartSuccess: suppressSmartSuccessFor.contains(id),
                isConnectivityFailure: isConnectivityFailure
            )
        }
        refreshDerived()
    }

    private func applyCancelledFetch(for id: String) {
        guard case .loading = providerStates[id], let info = providerInfo(for: id) else { return }
        setState(.loaded(ProviderQuota(
            providerId: id,
            providerName: info.displayName,
            headline: DisplayText { String(displayLocalized: "No data", bundle: .module) },
            lines: [],
            lastUpdated: Date(),
            error: DisplayText {
                String(displayLocalized: "Refresh canceled. Select Refresh to try again.", bundle: .module)
            }
        )), for: id)
    }
}
