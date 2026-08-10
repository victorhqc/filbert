import Core
import Foundation

// MARK: - Shared status resolver

/// Both the popover (`QuotaView`) and the menu-bar icon (`MenuBarStatusIcon`)
/// route through this type so they can never disagree on which line drives
/// the headline. No SwiftUI on purpose — `Tests/AppTests` exercises the
/// selection rules directly.
enum QuotaStatusResolver {
    enum Tier: Hashable {
        case good, warn, critical
    }

    enum Status: Equatable {
        case window(percentage: Double)
        case balance(used: Double?, total: Double, formattedAmount: String)
        case fallback
    }

    static func resolve(for quota: ProviderQuota) -> Status {
        if let percentageLine = firstPercentageLine(in: quota.lines) {
            if let pct = percentage(for: percentageLine) {
                return .window(percentage: pct)
            }
        }

        if let balanceLine = firstPositiveBalanceLine(in: quota.lines) {
            if let total = balanceLine.total, total > 0 {
                let amount = amountText(for: balanceLine) ?? ""
                return .balance(used: balanceLine.used, total: total, formattedAmount: amount)
            }
        }

        return .fallback
    }

    static func tier(for status: Status) -> Tier? {
        switch status {
        case let .window(percentage):
            switch percentage {
            case ..<50: .good
            case 50 ..< 80: .warn
            default: .critical
            }
        case let .balance(_, total, _):
            switch total {
            case ..<BalanceThresholds.low: .critical
            case BalanceThresholds.low ..< BalanceThresholds.ok: .warn
            default: .good
            }
        case .fallback:
            nil
        }
    }

    static func compactTier(for quota: ProviderQuota, at now: Date) -> Tier? {
        let status = resolve(for: quota)
        guard case .window = status,
              let line = firstPercentageLine(in: quota.lines),
              let weeklyPace = WeeklyBudgetPace(line: line, now: now)
        else {
            return tier(for: status)
        }
        return weeklyPace.tier
    }

    private static func firstPercentageLine(in lines: [UsageLine]) -> UsageLine? {
        lines.first { percentage(for: $0) != nil }
    }

    private static func firstPositiveBalanceLine(in lines: [UsageLine]) -> UsageLine? {
        lines.first { percentage(for: $0) == nil && ($0.total ?? 0) > 0 }
    }

    static func percentage(for line: UsageLine) -> Double? {
        if let pct = line.percentage {
            return pct
        }
        guard let used = line.used, let total = line.total, total > 0 else {
            return nil
        }
        return min(max(used / total * 100, 0), 100)
    }

    static func amountText(for line: UsageLine) -> String? {
        guard let total = line.total, total > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if let currency = line.unit, !currency.isEmpty {
            formatter.currencyCode = currency
        }
        return formatter.string(from: NSNumber(value: total))
    }

    static func clampedFraction(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}
