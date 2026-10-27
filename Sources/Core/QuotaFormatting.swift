import Foundation

/// Shared formatting so headline countdowns and UI labels use one identical,
/// localized format.
public enum QuotaFormatting {
    /// Returns a localized "resetting…" fallback when `resetDate` is in the past.
    public static func countdown(to resetDate: Date) -> String {
        countdown(to: resetDate, now: Date())
    }

    public static func countdown(to resetDate: Date, now: Date) -> String {
        let remaining = resetDate.timeIntervalSince(now)
        guard remaining > 0 else {
            return String(displayLocalized: "resetting…", bundle: .module)
        }
        let duration = timeLeft(remaining)
        return String(displayLocalized: "resets in \(duration)", bundle: .module)
    }

    private static func timeLeft(_ interval: TimeInterval) -> String {
        let minute: TimeInterval = 60
        let hour = 60 * minute
        let day = 24 * hour
        let minutes = max((interval / minute).rounded(.up), 1)
        let hours = (interval / hour).rounded()
        let (seconds, unit): (TimeInterval, NSCalendar.Unit) = if minutes < 60 {
            (minutes * minute, .minute)
        } else if hours < 24 {
            (hours * hour, .hour)
        } else {
            ((interval / day).rounded() * day, .day)
        }

        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = DisplayLanguage.locale
        formatter.calendar = calendar
        formatter.allowedUnits = unit
        formatter.unitsStyle = .full
        return formatter.string(from: seconds) ?? ""
    }

    /// `percentage` runs from 0 to 100. Rounds half to even, like `%.0f`.
    public static func percentage(_ percentage: Double) -> String {
        self.percentage(percentage, fractionLength: 0)
    }

    public static func percentage(_ percentage: Double, fractionLength: Int) -> String {
        percentage.formatted(
            .percent.scale(1).precision(.fractionLength(fractionLength)).locale(DisplayLanguage.locale)
        )
    }
}
