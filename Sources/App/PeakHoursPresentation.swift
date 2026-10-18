import Core
import Foundation

enum PeakHoursPresentation {
    static func rateText(for rate: PeakRatePresentation) -> String {
        switch rate {
        case let .multiplier(value):
            return String(displayLocalized: "\(value)× multiplier", bundle: .module)
        case let .fractionOfStandardRate(fraction):
            if fraction == 1 {
                return String(displayLocalized: "Standard credit rate", bundle: .module)
            }
            let percent = fraction.formatted(
                .percent.precision(.fractionLength(0 ... 1)).locale(DisplayLanguage.locale)
            )
            return String.localizedStringWithFormat(
                String(displayLocalized: "%@ credit rate", bundle: .module),
                percent
            )
        }
    }

    /// "Mon–Fri"-style label for the configured weekdays, or nil when the set
    /// is empty or spans the whole week (daily schedule).
    static func weekdayRangeText(for weekdays: Set<Int>) -> String? {
        guard !weekdays.isEmpty, weekdays.count < 7 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = DisplayLanguage.locale
        let symbols = calendar.shortWeekdaySymbols
        var runs: [[Int]] = []
        var currentRun: [Int] = []

        for day in weekdays.sorted() {
            if let last = currentRun.last, day == last + 1 {
                currentRun.append(day)
            } else {
                if !currentRun.isEmpty {
                    runs.append(currentRun)
                }
                currentRun = [day]
            }
        }
        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        let runTexts = runs.map { run -> String in
            guard let first = run.first, let last = run.last else { return "" }
            let firstSymbol = symbols[first - 1]
            return run.count == 1 ? firstSymbol : "\(firstSymbol)–\(symbols[last - 1])"
        }
        return runTexts.formatted(.list(type: .and).locale(DisplayLanguage.locale))
    }
}
