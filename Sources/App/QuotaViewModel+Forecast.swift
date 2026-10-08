import Core
import Foundation

extension QuotaViewModel {
    func recordAllowanceObservation(from quota: ProviderQuota, for providerId: String, at date: Date) {
        allowanceForecaster.record(quota.activityObservation, isStale: quota.isStale, for: providerId, at: date)
    }

    func hasAllowanceForecasts(for providerId: String) -> Bool {
        allowanceForecaster.hasHistory(for: providerId)
    }

    func allowanceForecastPresentation(
        for quota: ProviderQuota,
        providerId: String,
        at now: Date
    ) -> AllowanceForecastPresentation {
        AllowanceForecastPresentation(
            quota: quota,
            forecasts: allowanceForecaster.forecasts(for: providerId, at: now),
            now: now
        )
    }

    func interruptAllowanceForecasts() {
        allowanceForecaster.interruptAll(at: activityRuntime.now())
    }

    func clearAllowanceForecasts(for providerId: String) {
        allowanceForecaster.reset(for: providerId)
    }

    func handleSystemClockDidChange() {
        interruptAllowanceForecasts()
    }

    func installSystemClockObserver() {
        systemClockObserverToken = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemClockDidChange()
            }
        }
    }
}
