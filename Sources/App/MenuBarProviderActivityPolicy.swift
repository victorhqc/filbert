import Core
import Foundation

struct MenuBarProviderActivityPolicy: Sendable {
    static let consumptionAward = 10.0
    static let fastEntryAward = 30.0
    static let maximumScore = 60.0
    static let decayInterval: TimeInterval = 60

    private var baselines: [String: ObservationBaseline] = [:]
    private var scores: [String: ScoreState] = [:]
    private var fastRefreshingProviderIds: Set<String> = []

    @discardableResult
    mutating func recordSuccessfulResult(
        for providerId: String,
        observation: ProviderActivityObservation?,
        at date: Date
    ) -> Bool {
        let current = ObservationBaseline(observation: observation)
        guard let previous = baselines.updateValue(current, forKey: providerId) else {
            return false
        }
        guard previous.metrics != nil, current.metrics != nil else { return false }
        guard hasMeaningfulConsumption(from: previous, to: current) else { return false }

        award(Self.consumptionAward, to: providerId, at: date)
        return true
    }

    @discardableResult
    mutating func recordFastRefreshState(
        _ isActive: Bool,
        for providerId: String,
        at date: Date
    ) -> Bool {
        let wasActive = fastRefreshingProviderIds.contains(providerId)
        guard wasActive != isActive else { return false }

        if isActive {
            fastRefreshingProviderIds.insert(providerId)
            award(Self.fastEntryAward, to: providerId, at: date)
            return true
        }

        fastRefreshingProviderIds.remove(providerId)
        return false
    }

    mutating func resolve(at date: Date) -> [String: Double] {
        scores = scores.filter { _, state in
            effectiveScore(for: state, at: date) > 0
        }
        return effectiveScores(at: date)
    }

    func effectiveScores(at date: Date) -> [String: Double] {
        scores.reduce(into: [:]) { result, entry in
            let score = effectiveScore(for: entry.value, at: date)
            if score > 0 {
                result[entry.key] = score
            }
        }
    }

    func effectiveScore(for providerId: String, at date: Date) -> Double {
        guard let state = scores[providerId] else { return 0 }
        return effectiveScore(for: state, at: date)
    }

    func nextExpirationDate(at date: Date) -> Date? {
        scores.values
            .filter { effectiveScore(for: $0, at: date) > 0 }
            .map { $0.updatedAt.addingTimeInterval($0.points * Self.decayInterval) }
            .min()
    }

    func expirationDate(for providerId: String, at date: Date) -> Date? {
        guard let state = scores[providerId], effectiveScore(for: state, at: date) > 0 else {
            return nil
        }
        return state.updatedAt.addingTimeInterval(state.points * Self.decayInterval)
    }

    var activeScoreProviderIds: Set<String> {
        Set(scores.keys)
    }

    var baselineProviderIds: Set<String> {
        Set(baselines.keys)
    }

    mutating func reset(for providerId: String) {
        baselines.removeValue(forKey: providerId)
        scores.removeValue(forKey: providerId)
        fastRefreshingProviderIds.remove(providerId)
    }

    mutating func resetAll() {
        baselines.removeAll()
        scores.removeAll()
        fastRefreshingProviderIds.removeAll()
    }
}

private extension MenuBarProviderActivityPolicy {
    struct ScoreState: Sendable {
        let points: Double
        let updatedAt: Date
    }

    struct ObservationBaseline: Sendable {
        let metrics: [MetricKey: Decimal]?

        init(observation: ProviderActivityObservation?) {
            guard let observation else {
                metrics = nil
                return
            }

            var numericMetrics: [MetricKey: Decimal] = [:]
            for metric in observation.metrics {
                guard case let .number(value) = metric.value else { continue }
                let key = MetricKey(id: metric.id, kind: metric.kind)
                if numericMetrics[key] == nil {
                    numericMetrics[key] = value
                }
            }
            metrics = numericMetrics
        }
    }

    struct MetricKey: Hashable, Sendable {
        let id: String
        let kind: ProviderActivityMetric.Kind

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(kind.rawValue)
        }
    }

    func hasMeaningfulConsumption(
        from previous: ObservationBaseline,
        to current: ObservationBaseline
    ) -> Bool {
        guard let previousMetrics = previous.metrics,
              let currentMetrics = current.metrics
        else {
            return false
        }

        for (key, currentValue) in currentMetrics {
            guard let previousValue = previousMetrics[key] else { continue }
            switch key.kind {
            case .usage where currentValue > previousValue:
                return true
            case .credits where currentValue < previousValue:
                return true
            default:
                continue
            }
        }
        return false
    }

    mutating func award(_ points: Double, to providerId: String, at date: Date) {
        let currentScore = effectiveScore(for: providerId, at: date)
        let updatedAt = max(scores[providerId]?.updatedAt ?? date, date)
        let cappedScore = min(Self.maximumScore, currentScore + points)
        guard cappedScore > 0 else {
            scores.removeValue(forKey: providerId)
            return
        }
        scores[providerId] = ScoreState(points: cappedScore, updatedAt: updatedAt)
    }

    func effectiveScore(for state: ScoreState, at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(state.updatedAt))
        return max(0, state.points - elapsed / Self.decayInterval)
    }
}
