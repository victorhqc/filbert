import Foundation

public struct SmartRefreshPolicy: Sendable {
    public enum Cadence: Equatable, Sendable {
        case slow
        case fast
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
        for providerId: String
    ) -> Decision {
        let snapshot = ActivitySnapshot(observation: quota.activityObservation)
        var state = states[providerId] ?? State()

        guard let previousSnapshot = state.snapshot else {
            state.snapshot = snapshot
            states[providerId] = state
            return Decision(classification: .baseline, cadence: state.cadence)
        }

        state.snapshot = snapshot
        let reasons = previousSnapshot.changeReasons(comparedTo: snapshot)
        guard reasons.isEmpty else {
            state.cadence = .fast
            state.consecutiveUnchangedChecks = 0
            states[providerId] = state
            return Decision(
                classification: .changed,
                cadence: state.cadence,
                reasons: reasons
            )
        }

        if state.cadence == .fast {
            state.consecutiveUnchangedChecks += 1
            if state.consecutiveUnchangedChecks == Self.unchangedChecksBeforeSlowing {
                state.cadence = .slow
                state.consecutiveUnchangedChecks = 0
            }
        }
        states[providerId] = state
        return Decision(classification: .unchanged, cadence: state.cadence)
    }

    @discardableResult
    public mutating func recordFailure(for providerId: String) -> Cadence {
        var state = states[providerId] ?? State()
        state.cadence = .slow
        state.consecutiveUnchangedChecks = 0
        states[providerId] = state
        return state.cadence
    }

    public mutating func reset(for providerId: String) {
        states.removeValue(forKey: providerId)
    }

    public mutating func resetAll() {
        states.removeAll()
    }

    public func cadence(for providerId: String) -> Cadence {
        states[providerId]?.cadence ?? .slow
    }

    public func consecutiveUnchangedChecks(for providerId: String) -> Int {
        states[providerId]?.consecutiveUnchangedChecks ?? 0
    }

    private static let unchangedChecksBeforeSlowing = 3
}

private extension SmartRefreshPolicy {
    struct State: Sendable {
        var snapshot: ActivitySnapshot?
        var cadence: Cadence = .slow
        var consecutiveUnchangedChecks = 0
    }

    struct ActivitySnapshot: Equatable, Sendable {
        let metrics: [ProviderActivityMetric]
        let availability: ProviderAvailability?

        init(observation: ProviderActivityObservation?) {
            guard let observation else {
                metrics = []
                availability = nil
                return
            }

            assert(
                Set(observation.metrics.map(\.id)).count == observation.metrics.count,
                "Provider activity metric IDs must be unique."
            )
            metrics = observation.metrics.sorted { $0.id < $1.id }
            availability = observation.availability
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
