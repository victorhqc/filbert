import Core
import Foundation

/// The card's layout while a pool backs its exhausted limit group.
struct FallbackPoolLayout {
    let pool: UsageLine
    let exhaustedLines: [UsageLine]
    let otherLines: [UsageLine]

    init?(lines: [UsageLine], promotedPoolIds: Set<String>) {
        guard let pool = lines.first(where: { $0.id.map(promotedPoolIds.contains) ?? false }),
              let group = pool.fallbackForLimitGroup,
              Self.isExhausted(group, in: lines)
        else {
            return nil
        }
        self.pool = pool
        exhaustedLines = lines.filter { Self.isAtLimit($0, in: group) }
        otherLines = lines.filter { $0.id != pool.id && !Self.isAtLimit($0, in: group) }
    }

    static func isExhausted(_ group: String, in lines: [UsageLine]) -> Bool {
        lines.contains { isAtLimit($0, in: group) }
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
