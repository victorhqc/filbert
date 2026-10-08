import Foundation

public struct AllowanceForecaster: Sendable {
    let policy: AllowanceForecastPolicy
    private var histories: [String: [String: AllowanceHistory]] = [:]

    public init() {
        self.init(policy: .standard)
    }

    init(policy: AllowanceForecastPolicy) {
        self.policy = policy
    }

    public mutating func record(
        _ observation: ProviderActivityObservation?,
        for providerId: String,
        at now: Date
    ) {
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
}
