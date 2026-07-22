import Core
import Foundation

// MARK: - Shared status resolver (ui 10)

/// Pure value type that derives the menu-bar icon's display state from a
/// `ProviderQuota`.
///
/// The popover (`QuotaView`) and the menu-bar icon (`MenuBarStatusIcon`) both
/// route through this type so the icon and the popover rows can never disagree
/// on which line drives the headline (ui 10 AC3/AC4, ui 04 AC2, ui 08 AC3).
/// There is no SwiftUI here on purpose — `Tests/AppTests` exercises the
/// selection rules directly.
enum QuotaStatusResolver {
    enum Tier: Hashable {
        case good, warn, critical
    }

    /// The icon's resolved display state.
    enum Status: Equatable {
        /// Window-based provider: a percentage arc + `NN%` text (ui 10 AC3).
        case window(percentage: Double)
        /// Balance-based provider: a balance arc + currency text (ui 10 AC4).
        case balance(used: Double?, total: Double, formattedAmount: String)
        /// No usable data — fall back to the static SF Symbol (ui 10 AC5).
        case fallback
    }

    /// Resolves the icon state for a quota, applying the popover's line-
    /// selection rules (ui 10 AC3/AC4):
    /// 1. The first line with a non-nil percentage drives `window` mode.
    ///    The Claude Code provider orders its lines `[5-hour, weekly]`
    ///    (providers 02 AC5), so first-match gives the 5-hour-before-weekly
    ///    priority (ui 04 AC2, providers 01 AC5).
    /// 2. Otherwise the first positive-total balance-only line drives
    ///    `balance` mode, mirroring `headlineBalanceColor(for:)` (ui 08 AC3).
    /// 3. Otherwise `fallback`.
    static func resolve(for quota: ProviderQuota) -> Status {
        // AC3: percentage wins over balance when both are present on the same
        // quota (capped API plans, per core 01).
        if let percentageLine = firstPercentageLine(in: quota.lines) {
            if let pct = percentage(for: percentageLine) {
                return .window(percentage: pct)
            }
        }

        // AC4: first balance-only line with a positive total drives the ring.
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

    /// First line carrying a non-nil `percentage(for:)` value (ui 10 AC3).
    private static func firstPercentageLine(in lines: [UsageLine]) -> UsageLine? {
        lines.first { percentage(for: $0) != nil }
    }

    /// First balance-only line whose `total` is positive (ui 10 AC4), mirroring
    /// `headlineBalanceColor(for:)`'s selection rule (ui 08 AC3).
    private static func firstPositiveBalanceLine(in lines: [UsageLine]) -> UsageLine? {
        lines.first { percentage(for: $0) == nil && ($0.total ?? 0) > 0 }
    }

    /// Returns the line's percentage, deriving it from `used / total` when
    /// `percentage` is missing (e.g. monthly web-tool calls). Nil when there
    /// is no usable percentage data (ui 04 AC1).
    static func percentage(for line: UsageLine) -> Double? {
        if let pct = line.percentage {
            return pct
        }
        guard let used = line.used, let total = line.total, total > 0 else {
            return nil
        }
        return min(max(used / total * 100, 0), 100)
    }

    /// Currency-formatted amount for a balance-only line, using the line's
    /// `unit` as the currency code (e.g. "USD", "CNY"). Returns nil when the
    /// line has no positive total to format (ui 08 AC3).
    static func amountText(for line: UsageLine) -> String? {
        guard let total = line.total, total > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if let currency = line.unit, !currency.isEmpty {
            formatter.currencyCode = currency
        }
        return formatter.string(from: NSNumber(value: total))
    }

    /// Clamps `fraction` to `[0, 1]` before drawing — negative or >100 values
    /// never wrap around the track (ui 10 AC6).
    static func clampedFraction(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}
