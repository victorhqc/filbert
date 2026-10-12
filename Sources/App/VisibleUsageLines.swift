import Core

func visibleUsageLines(_ lines: [UsageLine]) -> [UsageLine] {
    lines.filter { line in
        QuotaStatusResolver.percentage(for: line) != nil
            || QuotaStatusResolver.amountText(for: line) != nil
            || !(line.details ?? []).isEmpty
    }
}
