import Foundation

/// Shared formatting so headline countdowns and UI labels use one identical,
/// localized format. Time phrases build on `Date.RelativeFormatStyle`, which
/// the OS localizes automatically.
public enum QuotaFormatting {
    /// Returns a localized "resetting…" fallback when `resetDate` is in the past.
    public static func countdown(to resetDate: Date) -> String {
        guard resetDate > Date() else {
            return String(localized: "resetting…")
        }
        let relative = resetDate.formatted(
            .relative(presentation: .named)
        )
        return String(localized: "resets \(relative)")
    }
}
