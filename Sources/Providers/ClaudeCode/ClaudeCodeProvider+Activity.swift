import Core
import Foundation

extension ClaudeCodeProvider {
    func activityObservation(from cache: StatuslineCache) -> ProviderActivityObservation {
        let now = Date().timeIntervalSince1970
        let entries = activityMetricEntries(from: cache.rateLimits)

        let freshMetrics = entries.compactMap { entry in
            isFresh(entry.window, cacheWrittenAt: cache.writtenAt, now: now)
                ? metric(for: entry, cacheWrittenAt: cache.writtenAt)
                : nil
        }
        if !freshMetrics.isEmpty {
            return ProviderActivityObservation(metrics: freshMetrics, freshness: .fresh)
        }

        // Every known window is stale: keep the figures for the UI-visible
        // last-known data while marking the observation stale so Core discards
        // it as evidence.
        let allMetrics = entries.compactMap { metric(for: $0, cacheWrittenAt: cache.writtenAt) }
        return ProviderActivityObservation(
            metrics: allMetrics,
            freshness: allMetrics.isEmpty ? .unknown : .stale
        )
    }

    private struct MetricEntry {
        let id: String
        let window: Window
        let length: TimeInterval
    }

    private func activityMetricEntries(from rateLimits: RateLimits?) -> [MetricEntry] {
        [
            (Self.fiveHourLineId, rateLimits?.fiveHour, UsageWindowDuration.fiveHours),
            (Self.weeklyLineId, rateLimits?.sevenDay, UsageWindowDuration.week),
        ].compactMap { id, window, length in
            window.map { MetricEntry(id: id, window: $0, length: length) }
        }
    }

    private func isFresh(_ window: Window, cacheWrittenAt: TimeInterval, now: TimeInterval) -> Bool {
        now - (window.writtenAt ?? cacheWrittenAt) <= Self.freshnessThreshold
    }

    private func metric(for entry: MetricEntry, cacheWrittenAt: TimeInterval) -> ProviderActivityMetric? {
        guard let percentage = entry.window.usedPercentage else { return nil }
        return ProviderActivityMetric(
            id: entry.id,
            kind: .usage,
            value: .number(Decimal(percentage)),
            forecastDescriptor: forecastDescriptor(for: entry, writtenAt: entry.window.writtenAt ?? cacheWrittenAt)
        )
    }

    private func forecastDescriptor(for entry: MetricEntry, writtenAt: TimeInterval) -> AllowanceForecastDescriptor? {
        guard let resetsAt = entry.window.resetsAt else { return nil }
        return AllowanceForecastDescriptor(
            accounting: .fixedPeriod(
                limit: 100,
                resetsAt: Date(timeIntervalSince1970: resetsAt),
                length: entry.length
            ),
            unit: .percentagePoints,
            resolution: 1,
            timing: .source(Date(timeIntervalSince1970: writtenAt)),
            usageLineId: entry.id
        )
    }
}
