import Core
import Foundation

func refreshDurationText(_ interval: TimeInterval) -> String {
    let seconds = Int(interval)
    if seconds < 60 {
        return String(displayLocalized: "\(seconds) seconds", bundle: .module)
    }

    return String(displayLocalized: "\(seconds / 60) minutes", bundle: .module)
}
