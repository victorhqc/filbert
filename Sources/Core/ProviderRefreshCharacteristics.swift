import Foundation

/// How a provider's refresh path affects its quota allowance. The absence of a
/// billing statement is `.unknown`, never `.documentedNonConsumption` — an
/// unverified request must not read as free (core 11 AC8).
public enum ProviderQuotaCostEvidence: Sendable, Equatable {
    case documentedNonConsumption
    case possibleConsumption
    case unknown
}

/// Provider-owned refresh limits. Core and App read these values off the
/// protocol and never branch on a provider ID (core 11 AC8).
public struct ProviderRefreshCharacteristics: Sendable, Equatable {
    public let costEvidence: ProviderQuotaCostEvidence
    /// Verified floor between requests, or `nil` when no limit is confirmed.
    public let minimumInterval: TimeInterval?
    /// Verified lower bound before retrying after a failure, or `nil`.
    public let retryDeadline: TimeInterval?
    public let canInvokeInference: Bool

    public init(
        costEvidence: ProviderQuotaCostEvidence = .unknown,
        minimumInterval: TimeInterval? = nil,
        retryDeadline: TimeInterval? = nil,
        canInvokeInference: Bool = false
    ) {
        self.costEvidence = costEvidence
        self.minimumInterval = minimumInterval
        self.retryDeadline = retryDeadline
        self.canInvokeInference = canInvokeInference
    }
}
