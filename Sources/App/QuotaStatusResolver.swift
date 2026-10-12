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
        case balance(amount: Double, formattedAmount: String)
        case credits(formattedAmount: String)
        case fallback
    }

    static func resolve(for quota: ProviderQuota, promotedPoolIds: Set<String> = []) -> Status {
        let layout = FallbackPoolLayout(lines: quota.lines, promotedPoolIds: promotedPoolIds)
        if let status = layout.flatMap({ poolStatus(of: $0.pool) }) {
            return status
        }

        if let percentageLine = firstPercentageLine(in: quota.lines) {
            if let pct = percentage(for: percentageLine) {
                return .window(percentage: pct)
            }
        }

        for line in quota.lines {
            guard let amount = currencyAmount(of: line), amount > 0 else { continue }
            return .balance(amount: amount, formattedAmount: amountText(for: line) ?? "")
        }

        return .fallback
    }

    static func isAtLimit(_ line: UsageLine) -> Bool {
        percentage(for: line).map { $0 >= 100 } ?? false
    }

    private static func poolStatus(of pool: UsageLine) -> Status? {
        guard let text = amountText(for: pool) else { return nil }
        if let amount = currencyAmount(of: pool) {
            return .balance(amount: amount, formattedAmount: text)
        }
        return .credits(formattedAmount: text)
    }

    static func firstCurrencyBalance(in lines: [UsageLine]) -> Double? {
        lines.lazy.compactMap(currencyAmount(of:)).first
    }

    /// `BalanceThresholds` are in currency, so credits never rank a provider.
    private static func currencyAmount(of line: UsageLine) -> Double? {
        guard let balance = line.balance,
              case let .finite(amount) = balance.amount,
              case .currency = balance.unit
        else {
            return nil
        }
        return NSDecimalNumber(decimal: amount).doubleValue
    }

    static func tier(for status: Status) -> Tier? {
        switch status {
        case let .window(percentage):
            switch percentage {
            case ..<50: .good
            case 50 ..< 80: .warn
            default: .critical
            }
        case let .balance(amount, _):
            switch amount {
            case ..<BalanceThresholds.low: .critical
            case BalanceThresholds.low ..< BalanceThresholds.ok: .warn
            default: .good
            }
        case .credits, .fallback:
            nil
        }
    }

    static func compactTier(for quota: ProviderQuota, promotedPoolIds: Set<String> = [], at now: Date) -> Tier? {
        let status = resolve(for: quota, promotedPoolIds: promotedPoolIds)
        guard case .window = status,
              let line = firstPercentageLine(in: quota.lines),
              let pace = BudgetPace(line: line, now: now)
        else {
            return tier(for: status)
        }
        return pace.tier
    }

    private static func firstPercentageLine(in lines: [UsageLine]) -> UsageLine? {
        lines.first { percentage(for: $0) != nil }
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
        if let balance = line.balance {
            return UsageAmountFormatting.string(for: balance)
        }
        guard percentage(for: line) == nil,
              let used = line.used,
              let currency = line.unit, !currency.isEmpty
        else {
            return nil
        }
        return UsageAmountFormatting.currency(NSNumber(value: used), code: currency)
    }

    static func clampedFraction(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}
