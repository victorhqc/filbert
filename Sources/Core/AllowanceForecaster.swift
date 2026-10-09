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
        isStale: Bool,
        for providerId: String,
        at now: Date
    ) {
        assert(
            observation.map { Self.sharedUsageLineIds(in: $0).isEmpty } ?? true,
            "Each forecast descriptor in an observation needs its own usage line ID"
        )
        accept(observation, isStale: isStale, for: providerId, at: now)
    }

    mutating func accept(
        _ observation: ProviderActivityObservation?,
        isStale: Bool,
        for providerId: String,
        at now: Date
    ) {
        guard let observation, observation.freshness == .fresh, !isStale else {
            update(providerId) { $0.pause() }
            return
        }

        var providerHistories = histories[providerId] ?? [:]
        let reportedIds = Set(observation.metrics.map(\.id))
        for (id, history) in providerHistories where !reportedIds.contains(id) {
            if now.timeIntervalSince(history.latest.time) > policy.maximumHorizon {
                providerHistories[id] = nil
            } else {
                providerHistories[id]?.pause()
            }
        }

        let sharedIds = Self.sharedUsageLineIds(in: observation)
        for metric in observation.metrics {
            guard let descriptor = metric.forecastDescriptor, !sharedIds.contains(descriptor.usageLineId) else {
                providerHistories[metric.id] = nil
                continue
            }
            guard let sample = AllowanceSample(metric: metric, descriptor: descriptor, now: now, policy: policy) else {
                providerHistories[metric.id]?.pause()
                continue
            }
            if providerHistories[metric.id] == nil {
                providerHistories[metric.id] = AllowanceHistory(baseline: sample, descriptor: descriptor)
            } else {
                providerHistories[metric.id]?.record(sample, descriptor: descriptor, policy: policy)
            }
        }
        histories[providerId] = providerHistories.isEmpty ? nil : providerHistories
    }

    /// Keyed by usage line ID.
    public func forecasts(for providerId: String, at now: Date) -> [String: AllowanceForecast] {
        let forecasts = histories[providerId, default: [:]].values.map { $0.forecast(at: now, policy: policy) }
        let grouped = Dictionary(grouping: forecasts, by: \.usageLineId)
        return grouped.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    public func hasHistory(for providerId: String) -> Bool {
        histories[providerId] != nil
    }

    public mutating func interruptAll(at now: Date) {
        for providerId in histories.keys {
            update(providerId) { $0.interrupt(at: now) }
        }
    }

    public mutating func reset(for providerId: String) {
        histories[providerId] = nil
    }
}

private extension AllowanceForecaster {
    static func sharedUsageLineIds(in observation: ProviderActivityObservation) -> Set<String> {
        let ids = observation.metrics.compactMap(\.forecastDescriptor?.usageLineId)
        return Set(Dictionary(grouping: ids) { $0 }.filter { $0.value.count > 1 }.keys)
    }

    mutating func update(_ providerId: String, _ change: (inout AllowanceHistory) -> Void) {
        histories[providerId] = histories[providerId]?.mapValues { history in
            var history = history
            change(&history)
            return history
        }
    }
}
