import Core
import Foundation

extension QuotaViewModel {
    func recordAllowanceObservation(from quota: ProviderQuota, for providerId: String, at date: Date) {
        allowanceForecaster.record(quota.activityObservation, isStale: quota.isStale, for: providerId, at: date)
        fallbackPoolTracker.record(quota, for: providerId)
    }

    func promotedFallbackPoolIds(for providerId: String) -> Set<String> {
        fallbackPoolTracker.promotedPoolIds(for: providerId)
    }

    func fallbackPoolLayout(for quota: ProviderQuota, providerId: String) -> FallbackPoolLayout? {
        FallbackPoolLayout(lines: quota.lines, promotedPoolIds: promotedFallbackPoolIds(for: providerId))
    }

    func hasAllowanceForecasts(for providerId: String) -> Bool {
        allowanceForecaster.hasHistory(for: providerId)
    }

    /// A timeline tick can predate the latest sample, which would read as
    /// paused until the next tick.
    func allowanceForecastPresentation(
        for quota: ProviderQuota,
        providerId: String,
        at timelineDate: Date
    ) -> AllowanceForecastPresentation {
        let now = max(timelineDate, activityRuntime.now())
        return AllowanceForecastPresentation(
            quota: quota,
            forecasts: allowanceForecaster.forecasts(for: providerId, at: now),
            now: now,
            fallbackPool: fallbackPoolLayout(for: quota, providerId: providerId)
        )
    }

    func interruptAllowanceForecasts() {
        allowanceForecaster.interruptAll(at: activityRuntime.now())
    }

    func clearAllowanceForecasts(for providerId: String) {
        allowanceForecaster.reset(for: providerId)
        fallbackPoolTracker.reset(for: providerId)
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
