import Core
import Foundation

extension QuotaViewModel {
    func recordAllowanceObservation(_ observation: ProviderActivityObservation?, for providerId: String) {
        allowanceForecaster.record(observation, for: providerId, at: forecastNow())
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
        allowanceForecaster.interruptAll()
    }

    func clearAllowanceForecasts(for providerId: String) {
        allowanceForecaster.reset(for: providerId)
    }
}
