import Core

func filteredBalanceLines(
    _ lines: [UsageLine],
    isPercentageLine: (UsageLine) -> Bool
) -> [UsageLine] {
    let positiveBalanceTotals = lines.compactMap { line -> Double? in
        guard !isPercentageLine(line) else { return nil }
        guard let total = line.total, total > 0 else { return nil }
        return total
    }
    let cents = positiveBalanceTotals.map { Int(($0 * 100).rounded()) }
    let hasDuplicates = Set(cents).count < cents.count

    var firstBalanceKept = false
    return lines.filter { line in
        guard !isPercentageLine(line) else { return true }
        guard let total = line.total, total > 0 else { return false }
        if hasDuplicates {
            if firstBalanceKept {
                return false
            }
            firstBalanceKept = true
            return true
        }
        return true
    }
}
