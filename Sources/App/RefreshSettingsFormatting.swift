import Foundation

func refreshDurationText(_ interval: TimeInterval) -> String {
    let seconds = Int(interval)
    if seconds < 60 {
        return String.localizedStringWithFormat(
            String(localized: "%lld seconds"),
            seconds
        )
    }

    let minutes = seconds / 60
    if minutes == 1 {
        return String(localized: "1 minute")
    }
    return String.localizedStringWithFormat(
        String(localized: "%lld minutes"),
        minutes
    )
}
