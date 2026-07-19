import Foundation

/// Shared formatting helpers so headline countdowns and UI labels use
/// one identical, localized format (providers 01 AC5/AC7).
///
/// Time phrases build on `Date.RelativeFormatStyle`, which the OS
/// localizes automatically.
public enum QuotaFormatting {

    /// Returns a localized countdown string for a future reset date.
    ///
    /// Uses `Date.RelativeFormatStyle` so the duration portion ("in 3 hours",
    /// "in 45 minutes") is automatically localized by the OS. The wrapping
    /// "resets …" prefix is also localized via `String(localized:)`.
    ///
    /// If the date is in the past, returns a localized "resetting…" fallback.
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
