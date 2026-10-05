import Foundation

/// An unverified request is `.unknown`, never `.documentedNonConsumption` —
/// the absence of a billing statement must not read as free.
public enum ProviderQuotaCostEvidence: Sendable, Equatable {
    case documentedNonConsumption
    case possibleConsumption
    case unknown
}

public struct ProviderRefreshCharacteristics: Sendable, Equatable {
    public let costEvidence: ProviderQuotaCostEvidence
    public let minimumInterval: TimeInterval?
    public let canInvokeInference: Bool

    public init(
        costEvidence: ProviderQuotaCostEvidence = .unknown,
        minimumInterval: TimeInterval? = nil,
        canInvokeInference: Bool = false
    ) {
        self.costEvidence = costEvidence
        self.minimumInterval = minimumInterval
        self.canInvokeInference = canInvokeInference
    }
}
