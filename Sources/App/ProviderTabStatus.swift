import Core
import Foundation

struct ProviderTabStatus: Equatable {
    enum Value: Equatable {
        case text(String)
        case progress
        case warning(String)
        case empty
    }

    let ringFraction: Double
    let tier: QuotaStatusResolver.Tier?
    let value: Value
    /// Percentages take the tier color like the stacked card; amounts stay
    /// neutral because the full ring already carries the balance tier.
    let colorsValue: Bool

    static let emptyTrack = ProviderTabStatus(ringFraction: 0, tier: nil, value: .empty, colorsValue: false)

    static func make(state: ProviderState, errorMessage: String?, at now: Date) -> ProviderTabStatus {
        let base = baseStatus(for: state, at: now)
        guard let errorMessage else { return base }
        return ProviderTabStatus(
            ringFraction: base.ringFraction,
            tier: base.tier,
            value: .warning(errorMessage),
            colorsValue: false
        )
    }

    private static func baseStatus(for state: ProviderState, at now: Date) -> ProviderTabStatus {
        switch state {
        case let .loaded(quota):
            loadedStatus(for: quota, at: now)
        case .loading:
            ProviderTabStatus(ringFraction: 0, tier: nil, value: .progress, colorsValue: false)
        case .unconfigured, .setup, .error:
            emptyTrack
        }
    }

    private static func loadedStatus(for quota: ProviderQuota, at now: Date) -> ProviderTabStatus {
        let tier = QuotaStatusResolver.compactTier(for: quota, at: now)
        switch QuotaStatusResolver.resolve(for: quota) {
        case let .window(percentage):
            return ProviderTabStatus(
                ringFraction: QuotaStatusResolver.clampedFraction(percentage / 100),
                tier: tier,
                value: .text(QuotaFormatting.percentage(percentage)),
                colorsValue: true
            )
        case let .balance(_, formattedAmount):
            return ProviderTabStatus(ringFraction: 1, tier: tier, value: .text(formattedAmount), colorsValue: false)
        case let .credits(formattedAmount):
            return ProviderTabStatus(ringFraction: 0, tier: nil, value: .text(formattedAmount), colorsValue: false)
        case .fallback:
            return emptyTrack
        }
    }
}
