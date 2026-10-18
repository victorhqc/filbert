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
}
