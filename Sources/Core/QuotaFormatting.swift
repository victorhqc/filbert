import Foundation

/// Shared formatting so headline countdowns and UI labels use one identical,
/// localized format.
public enum QuotaFormatting {
    /// Returns a localized "resetting…" fallback when `resetDate` is in the past.
    public static func countdown(to resetDate: Date) -> String {
        guard resetDate > Date() else {
            return String(displayLocalized: "resetting…", bundle: .module)
        }
        let relative = resetDate.formatted(
            .relative(presentation: .named).locale(DisplayLanguage.locale)
        )
        return String(displayLocalized: "resets \(relative)", bundle: .module)
    }

    /// `percentage` runs from 0 to 100. Rounds half to even, like `%.0f`.
    public static func percentage(_ percentage: Double) -> String {
        percentage.formatted(.percent.scale(1).precision(.fractionLength(0)).locale(DisplayLanguage.locale))
    }
}
