import Core

/// Providers decide which lines exist; the card only hides a line that has
/// nothing to show (core 13).
func visibleUsageLines(_ lines: [UsageLine]) -> [UsageLine] {
    lines.filter { line in
        QuotaStatusResolver.percentage(for: line) != nil
            || QuotaStatusResolver.amountText(for: line) != nil
            || !(line.details ?? []).isEmpty
    }
}
