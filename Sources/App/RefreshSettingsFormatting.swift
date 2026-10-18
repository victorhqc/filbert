import Core
import Foundation

func refreshDurationText(_ interval: TimeInterval) -> String {
    let seconds = Int(interval)
    if seconds < 60 {
        return String.localizedStringWithFormat(
            String(displayLocalized: "%lld seconds", bundle: .module),
            seconds
        )
    }

    let minutes = seconds / 60
    if minutes == 1 {
        return String(displayLocalized: "1 minute", bundle: .module)
    }
    return String.localizedStringWithFormat(
        String(displayLocalized: "%lld minutes", bundle: .module),
        minutes
    )
}
