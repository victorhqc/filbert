import Foundation

public struct SmartRefreshPolicy: Sendable {
    public enum Cadence: Equatable, Sendable {
        case slow
        case fast
        case cooldown
    }

    public enum Classification: Equatable, Sendable {
        case baseline
        case unchanged
        case changed
    }

    public enum ChangeReason: String, CaseIterable, Hashable, Sendable {
        case usage
        case credits
        case availability
    }

    public struct Decision: Equatable, Sendable {
        public let classification: Classification
        public let cadence: Cadence
        public let reasons: Set<ChangeReason>

        init(
            classification: Classification,
            cadence: Cadence,
            reasons: Set<ChangeReason> = []
        ) {
            self.classification = classification
            self.cadence = cadence
            self.reasons = reasons
        }
    }

    private var states: [String: State] = [:]

    public init() {}

    @discardableResult
    public mutating func recordSuccess(
        _ quota: ProviderQuota,
        for providerId: String,
        at elapsed: TimeInterval,
        quietWindow: TimeInterval
    ) -> Decision {
        var state = states[providerId] ?? State()

        guard let observation = quota.activityObservation,
              observation.freshness != .stale
        else {
            // Absent or provider-known-stale data renews nothing and keeps the
            // accepted baseline.
            states[providerId] = state
            return state.unchanged(at: elapsed, quietWindow: quietWindow)
        }

        let incoming = ActivitySnapshot(observation: observation)
        guard incoming.hasComparisonData else {
            states[providerId] = state
            return state.unchanged(at: elapsed, quietWindow: quietWindow)
        }

        guard let previous = state.snapshot else {
            state.snapshot = incoming
            states[providerId] = state
            return Decision(
                classification: .baseline,
                cadence: state.cadence(at: elapsed, quietWindow: quietWindow)
            )
        }

        let snapshot = previous.merged(with: incoming)
        let reasons = previous.changeReasons(comparedTo: snapshot)
        state.snapshot = snapshot
        guard reasons.isEmpty else {
            state.activityTime = elapsed
            states[providerId] = state
            return Decision(
                classification: .changed,
                cadence: .fast,
                reasons: reasons
            )
        }

        states[providerId] = state
        return state.unchanged(at: elapsed, quietWindow: quietWindow)
    }

    @discardableResult
    public mutating func recordActivityHint(
        for providerId: String,
        at elapsed: TimeInterval
    ) -> Cadence {
        var state = states[providerId] ?? State()
        state.activityTime = elapsed
        states[providerId] = state
        return .fast
    }

    @discardableResult
    public mutating func recordFailure(for providerId: String) -> Cadence {
        var state = states[providerId] ?? State()
        state.activityTime = nil
        states[providerId] = state
        return .slow
    }

    public mutating func reset(for providerId: String) {
        states.removeValue(forKey: providerId)
    }

    public mutating func resetAll() {
        states.removeAll()
    }

    public func cadence(
        for providerId: String,
        at elapsed: TimeInterval,
        quietWindow: TimeInterval
    ) -> Cadence {
        states[providerId]?.cadence(at: elapsed, quietWindow: quietWindow) ?? .slow
    }

    public func nextPhaseBoundary(
        for providerId: String,
        at elapsed: TimeInterval,
        quietWindow: TimeInterval
    ) -> TimeInterval? {
        states[providerId]?.nextPhaseBoundary(at: elapsed, quietWindow: quietWindow)
    }
}

private extension SmartRefreshPolicy {
    struct State: Sendable {
        var snapshot: ActivitySnapshot?
        var activityTime: TimeInterval?

        func cadence(at elapsed: TimeInterval, quietWindow: TimeInterval) -> Cadence {
            guard let activityTime else { return .slow }
            let since = elapsed - activityTime
            if since < quietWindow {
                return .fast
            }
            if since < 2 * quietWindow {
                return .cooldown
            }
            return .slow
        }

        func unchanged(at elapsed: TimeInterval, quietWindow: TimeInterval) -> Decision {
            Decision(classification: .unchanged, cadence: cadence(at: elapsed, quietWindow: quietWindow))
        }

        func nextPhaseBoundary(at elapsed: TimeInterval, quietWindow: TimeInterval) -> TimeInterval? {
            guard let activityTime else { return nil }
            let since = elapsed - activityTime
            if since < quietWindow {
                return activityTime + quietWindow
            }
            if since < 2 * quietWindow {
                return activityTime + 2 * quietWindow
            }
            return nil
        }
    }

    struct ActivitySnapshot: Equatable, Sendable {
        let metrics: [ProviderActivityMetric]
        let availability: ProviderAvailability?

        init(observation: ProviderActivityObservation) {
            assert(
                Set(observation.metrics.map(\.id)).count == observation.metrics.count,
                "Provider activity metric IDs must be unique."
            )
            metrics = observation.metrics.sorted { $0.id < $1.id }
            availability = observation.availability
        }

        private init(metrics: [ProviderActivityMetric], availability: ProviderAvailability?) {
            self.metrics = metrics
            self.availability = availability
        }

        var hasComparisonData: Bool {
            !metrics.isEmpty || isKnown(availability)
        }

        /// Keeps the previous value for any field the newer observation omits,
        /// so an empty or availability-only result cannot drop the accepted
        /// baseline.
        func merged(with newer: Self) -> Self {
            ActivitySnapshot(
                metrics: newer.metrics.isEmpty ? metrics : newer.metrics,
                availability: isKnown(newer.availability) ? newer.availability : availability
            )
        }

        func changeReasons(comparedTo current: Self) -> Set<ChangeReason> {
            var reasons: Set<ChangeReason> = []

            if !metrics.isEmpty, !current.metrics.isEmpty {
                let previousMetrics = Dictionary(
                    metrics.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let currentMetrics = Dictionary(
                    current.metrics.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for metricId in Set(previousMetrics.keys).union(currentMetrics.keys) {
                    switch (previousMetrics[metricId], currentMetrics[metricId]) {
                    case let (.some(previous), .some(next)) where previous != next:
                        reasons.formUnion([previous.kind.reason, next.kind.reason])
                    case let (.some(previous), .none):
                        reasons.insert(previous.kind.reason)
                    case let (.none, .some(next)):
                        reasons.insert(next.kind.reason)
                    case (.none, .none), (.some, .some):
                        break
                    }
                }
            }

            if isKnown(availability), isKnown(current.availability), availability != current.availability {
                reasons.insert(.availability)
            }
            return reasons
        }
    }
}

private extension ProviderActivityMetric.Kind {
    var reason: SmartRefreshPolicy.ChangeReason {
        switch self {
        case .usage:
            .usage
        case .credits:
            .credits
        }
    }
}

private func isKnown(_ availability: ProviderAvailability?) -> Bool {
    switch availability {
    case .some(.available), .some(.unavailable):
        true
    case .none, .some(.unknown):
        false
    }
}
