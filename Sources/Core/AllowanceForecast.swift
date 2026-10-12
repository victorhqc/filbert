import Foundation

public struct AllowanceForecast: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case learning
        case estimated(depletesAt: Date)
        case beyondReset(resetsAt: Date)
        case quiet
        case tooFarApart
        case paused
        case exhausted
        case insufficient
    }

    public let usageLineId: String
    public let state: State
    public let observedAt: Date
    public let evidenceSpan: TimeInterval?
    public let isApproximate: Bool
    /// Paused after the projected depletion time, or without an estimate and
    /// closer to the limit than the engine can measure a rate.
    public let isUncertainNearLimit: Bool

    public init(
        usageLineId: String,
        state: State,
        observedAt: Date,
        evidenceSpan: TimeInterval? = nil,
        isApproximate: Bool = false,
        isUncertainNearLimit: Bool = false
    ) {
        self.usageLineId = usageLineId
        self.state = state
        self.observedAt = observedAt
        self.evidenceSpan = evidenceSpan
        self.isApproximate = isApproximate
        self.isUncertainNearLimit = isUncertainNearLimit
    }

    func observationAge(at now: Date) -> TimeInterval {
        now.timeIntervalSince(observedAt)
    }

    public func remainingUse(at now: Date) -> TimeInterval? {
        guard case let .estimated(depletesAt) = state else { return nil }
        return max(depletesAt.timeIntervalSince(now), 0)
    }
}
