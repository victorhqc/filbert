import Foundation

/// History stays in memory. Never persist it.
public struct AllowanceForecaster: Sendable {
    public let policy: AllowanceForecastPolicy
    private var histories: [String: [String: AllowanceHistory]] = [:]

    public init(policy: AllowanceForecastPolicy = .standard) {
        self.policy = policy
    }

    public mutating func record(
        _ observation: ProviderActivityObservation?,
        for providerId: String,
        at now: Date
    ) {
        // Smart refresh counts `.unknown` as activity (core 11). History does not.
        guard let observation, observation.freshness == .fresh else { return }

        var providerHistories = histories[providerId] ?? [:]
        for metric in observation.metrics {
            guard let descriptor = metric.forecastDescriptor else {
                providerHistories[metric.id] = nil
                continue
            }
            guard let sample = AllowanceSample(
                metric: metric,
                descriptor: descriptor,
                now: now,
                policy: policy
            ) else {
                continue
            }
            if var history = providerHistories[metric.id] {
                history.record(sample, descriptor: descriptor, policy: policy)
                providerHistories[metric.id] = history
            } else {
                providerHistories[metric.id] = AllowanceHistory(baseline: sample, descriptor: descriptor)
            }
        }
        histories[providerId] = providerHistories.isEmpty ? nil : providerHistories
    }

    /// Keyed by usage line ID.
    public func forecasts(for providerId: String, at now: Date) -> [String: AllowanceForecast] {
        var forecasts: [String: AllowanceForecast] = [:]
        for history in histories[providerId, default: [:]].values {
            let forecast = history.forecast(at: now, policy: policy)
            forecasts[forecast.usageLineId] = forecast
        }
        return forecasts
    }

    public func hasHistory(for providerId: String) -> Bool {
        histories[providerId] != nil
    }

    /// Sleep, wake, and clock changes break contiguity.
    public mutating func interruptAll() {
        for (providerId, providerHistories) in histories {
            histories[providerId] = providerHistories.mapValues { history in
                var history = history
                history.interrupt()
                return history
            }
        }
    }

    public mutating func reset(for providerId: String) {
        histories[providerId] = nil
    }

    public mutating func resetAll() {
        histories.removeAll()
    }
}
