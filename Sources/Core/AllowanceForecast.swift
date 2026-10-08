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

    public init(
        usageLineId: String,
        state: State,
        observedAt: Date,
        evidenceSpan: TimeInterval? = nil,
        isApproximate: Bool = false
    ) {
        self.usageLineId = usageLineId
        self.state = state
        self.observedAt = observedAt
        self.evidenceSpan = evidenceSpan
        self.isApproximate = isApproximate
    }

    func observationAge(at now: Date) -> TimeInterval {
        now.timeIntervalSince(observedAt)
    }

    public func remainingUse(at now: Date) -> TimeInterval? {
        guard case let .estimated(depletesAt) = state else { return nil }
        return max(depletesAt.timeIntervalSince(now), 0)
    }
}
