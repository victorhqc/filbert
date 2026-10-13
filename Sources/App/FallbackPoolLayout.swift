import Core
import Foundation

/// The card's layout while a pool backs its exhausted limit group.
struct FallbackPoolLayout {
    let pool: UsageLine
    let exhaustedLines: [UsageLine]
    let otherLines: [UsageLine]

    init?(lines: [UsageLine]) {
        guard let pool = lines.first(where: { Self.canBack($0, in: lines) }),
              let group = pool.fallbackForLimitGroup
        else {
            return nil
        }
        self.pool = pool
        exhaustedLines = lines.filter { Self.isAtLimit($0, in: group) }
        otherLines = lines.filter { $0.id != pool.id && !Self.isAtLimit($0, in: group) }
    }

    private static func canBack(_ pool: UsageLine, in lines: [UsageLine]) -> Bool {
        guard let group = pool.fallbackForLimitGroup, hasBalance(pool) else { return false }
        return lines.contains { isAtLimit($0, in: group) }
    }

    private static func hasBalance(_ pool: UsageLine) -> Bool {
        switch pool.balance?.amount {
        case let .finite(amount)?: amount > 0
        case .unlimited?: true
        case nil: false
        }
    }

    /// The pool row, with one small line per exhausted limit.
    func poolLine() -> UsageLine {
        UsageLine(
            label: pool.label,
            used: pool.used,
            total: pool.total,
            percentage: pool.percentage,
            unit: pool.unit,
            balance: pool.balance,
            resetDate: pool.resetDate,
            windowDuration: pool.windowDuration,
            details: (pool.details ?? []) + exhaustedLines.map(exhaustedDetail(for:)),
            id: pool.id,
            limitGroup: pool.limitGroup,
            fallbackForLimitGroup: pool.fallbackForLimitGroup
        )
    }

    private func exhaustedDetail(for line: UsageLine) -> UsageDetail {
        guard let resetDate = line.resetDate else {
            return UsageDetail(label: line.label, value: String(localized: "Limit reached"))
        }
        return UsageDetail(
            label: line.label,
            value: String.localizedStringWithFormat(
                String(localized: "Limit reached · %@"),
                QuotaFormatting.countdown(to: resetDate)
            )
        )
    }

    private static func isAtLimit(_ line: UsageLine, in group: String) -> Bool {
        line.limitGroup == group && QuotaStatusResolver.isAtLimit(line)
    }
}
