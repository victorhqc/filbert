import Core
import Foundation

/// Memory-only, and cleared with the forecast history.
struct FallbackPoolTracker {
    private struct Pool {
        let balance: Decimal
        let isPromoted: Bool
    }

    private var pools: [String: [String: Pool]] = [:]

    /// A pool is promoted once its balance falls into or during the
    /// exhaustion of its group, and stays promoted until the group recovers.
    mutating func record(_ quota: ProviderQuota, for providerId: String) {
        guard quota.activityObservation?.freshness == .fresh, !quota.isStale else { return }

        var recorded: [String: Pool] = [:]
        for line in quota.lines {
            guard let id = line.id,
                  let group = line.fallbackForLimitGroup,
                  case let .finite(balance)? = line.balance?.amount
            else {
                continue
            }
            let previous = pools[providerId]?[id]
            let decreased = previous.map { balance < $0.balance } ?? false
            let isExhausted = FallbackPoolLayout.isExhausted(group, in: quota.lines)
            recorded[id] = Pool(
                balance: balance,
                isPromoted: isExhausted && (decreased || previous?.isPromoted == true)
            )
        }
        pools[providerId] = recorded.isEmpty ? nil : recorded
    }

    func promotedPoolIds(for providerId: String) -> Set<String> {
        Set(pools[providerId, default: [:]].filter(\.value.isPromoted).keys)
    }

    mutating func reset(for providerId: String) {
        pools[providerId] = nil
    }
}
