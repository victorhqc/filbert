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

    /// A refresh that can invoke inference stays in the automatic fast phase no
    /// longer than this, even while observations keep changing.
    public static let inferenceEpisodeCap: TimeInterval = 10 * 60

    /// The single derived cooldown cadence. Kept here so the scheduler and the
    /// settings copy cannot drift apart.
    public static func cooldownInterval(
        slowInterval: TimeInterval,
        fastInterval: TimeInterval
    ) -> TimeInterval {
        min(slowInterval, max(2 * fastInterval, 60))
    }

    private var states: [String: State] = [:]

    public init() {}

    @discardableResult
    public mutating func recordSuccess(
        _ quota: ProviderQuota,
        for providerId: String,
        at elapsed: TimeInterval,
        quietWindow: TimeInterval,
        canInvokeInference: Bool = false
    ) -> Decision {
        var state = states[providerId] ?? State()
        state.canInvokeInference = canInvokeInference
        state.expirePhases(at: elapsed, quietWindow: quietWindow)

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
        guard !reasons.isEmpty else {
            states[providerId] = state
            return state.unchanged(at: elapsed, quietWindow: quietWindow)
        }

        state.beginAutomaticFast(at: elapsed)
        states[providerId] = state
        return Decision(
            classification: .changed,
            cadence: state.cadence(at: elapsed, quietWindow: quietWindow),
            reasons: reasons
        )
    }

    @discardableResult
    public mutating func recordActivityHint(
        for providerId: String,
        at elapsed: TimeInterval,
        quietWindow: TimeInterval,
        canInvokeInference: Bool = false
    ) -> Cadence {
        var state = states[providerId] ?? State()
        state.canInvokeInference = canInvokeInference
        state.expirePhases(at: elapsed, quietWindow: quietWindow)
        state.beginAutomaticFast(at: elapsed)
        states[providerId] = state
        return state.cadence(at: elapsed, quietWindow: quietWindow)
    }

    @discardableResult
    public mutating func recordFailure(
        for providerId: String,
        at elapsed: TimeInterval,
        quietWindow: TimeInterval
    ) -> Cadence {
        var state = states[providerId] ?? State()
        // Elapsed transitions must resolve before the failure clears the
        // episode, or a cap crossed since the last advance would never
        // materialize its lockout.
        state.expirePhases(at: elapsed, quietWindow: quietWindow)
        state.activityTime = nil
        state.episodeStart = nil
        state.extensionDeadline = nil
        states[providerId] = state
        return state.cadence(at: elapsed, quietWindow: quietWindow)
    }

    public mutating func recordExtension(
        for providerId: String,
        duration: TimeInterval,
        at elapsed: TimeInterval
    ) {
        var state = states[providerId] ?? State()
        state.extensionDeadline = elapsed + duration
        states[providerId] = state
    }

    public mutating func stopExtension(for providerId: String) {
        states[providerId]?.extensionDeadline = nil
    }

    public func extensionDeadline(for providerId: String) -> TimeInterval? {
        states[providerId]?.extensionDeadline
    }

    /// Expires time-driven phases (the inference episode cap, an extension
    /// deadline, and a finished lockout) without a completed request.
    public mutating func advance(
        for providerId: String,
        at elapsed: TimeInterval,
        quietWindow: TimeInterval
    ) {
        guard var state = states[providerId] else { return }
        state.expirePhases(at: elapsed, quietWindow: quietWindow)
        states[providerId] = state
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
        var episodeStart: TimeInterval?
        var lockoutUntil: TimeInterval?
        var extensionDeadline: TimeInterval?
        var canInvokeInference = false

        func isLockedOut(at elapsed: TimeInterval) -> Bool {
            guard let lockoutUntil else { return false }
            return elapsed < lockoutUntil
        }

        mutating func beginAutomaticFast(at elapsed: TimeInterval) {
            guard !isLockedOut(at: elapsed) else { return }
            // The episode starts on entry and never renews while it is
            // running; a revived window needs a fresh start or the cap could
            // never fire.
            if canInvokeInference, episodeStart == nil {
                episodeStart = elapsed
            }
            activityTime = elapsed
        }

        mutating func expirePhases(at elapsed: TimeInterval, quietWindow: TimeInterval) {
            resolveInferenceEpisode(at: elapsed, quietWindow: quietWindow)
            if let deadline = extensionDeadline, elapsed >= deadline {
                extensionDeadline = nil
            }
            if let until = lockoutUntil, elapsed >= until {
                lockoutUntil = nil
            }
        }

        /// Resolves the inference episode in chronological order, so a late
        /// advance (for example after sleep) cannot invent a lockout.
        private mutating func resolveInferenceEpisode(at elapsed: TimeInterval, quietWindow: TimeInterval) {
            guard canInvokeInference else { return }

            if let start = episodeStart {
                let capTime = start + SmartRefreshPolicy.inferenceEpisodeCap
                let windowEnd = (activityTime ?? start) + 2 * quietWindow
                if windowEnd < capTime {
                    // The window lapses strictly before the cap, so the episode
                    // ends naturally with no lockout. `activityTime` stays so a
                    // longer quiet window can re-open it.
                    if elapsed >= windowEnd {
                        episodeStart = nil
                    }
                } else if elapsed >= capTime {
                    activityTime = nil
                    episodeStart = nil
                    lockoutUntil = capTime + quietWindow
                }
            }

            if episodeStart == nil, !isLockedOut(at: elapsed) {
                guard let activity = activityTime, elapsed < activity + 2 * quietWindow else { return }
                episodeStart = elapsed
            }
        }

        func cadence(at elapsed: TimeInterval, quietWindow: TimeInterval) -> Cadence {
            if let extensionDeadline, elapsed < extensionDeadline {
                return .fast
            }
            if isLockedOut(at: elapsed) {
                return .slow
            }
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

        func nextPhaseBoundary(at elapsed: TimeInterval, quietWindow: TimeInterval) -> TimeInterval? {
            // An extension overrides cadence but must not hide the underlying
            // cap or lockout, or a failure could erase a required lockout.
            var boundaries: [TimeInterval] = []
            if let extensionDeadline {
                boundaries.append(extensionDeadline)
            }
            if let lockoutUntil {
                boundaries.append(lockoutUntil)
            }
            if let activityTime {
                let since = elapsed - activityTime
                if since < quietWindow {
                    boundaries.append(activityTime + quietWindow)
                } else if since < 2 * quietWindow {
                    boundaries.append(activityTime + 2 * quietWindow)
                }
            }
            if canInvokeInference, let episodeStart {
                boundaries.append(episodeStart + SmartRefreshPolicy.inferenceEpisodeCap)
            }
            return boundaries.filter { $0 > elapsed }.min()
        }

        func unchanged(at elapsed: TimeInterval, quietWindow: TimeInterval) -> Decision {
            Decision(classification: .unchanged, cadence: cadence(at: elapsed, quietWindow: quietWindow))
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

        /// Keeps the previous value for any metric the newer observation omits,
        /// so a partial result cannot drop the baseline or fake a removal.
        func merged(with newer: Self) -> Self {
            let mergedMetrics: [ProviderActivityMetric]
            if newer.metrics.isEmpty {
                mergedMetrics = metrics
            } else {
                var byId = Dictionary(metrics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for metric in newer.metrics {
                    byId[metric.id] = metric
                }
                mergedMetrics = byId.values.sorted { $0.id < $1.id }
            }
            return ActivitySnapshot(
                metrics: mergedMetrics,
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
                    case let (.some(previous), .some(next)) where !previous.measuresSameValue(as: next):
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
