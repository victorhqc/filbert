import Core
import Foundation

/// Remembers the highest percentage seen for each window in its current period.
/// The statusline reports one point less than `/usage` for the same window, so
/// reading whichever wrote last would show a decrease on every switch.
///
/// Lives in memory only and starts empty on each launch (providers 17 AC3).
final class ClaudeCodeWindowPeaks: @unchecked Sendable {
    private struct Peak {
        /// The first reset reported in this period. Later resets are compared
        /// with it, not with the previous one, so small moves cannot add up.
        let periodResetsAt: TimeInterval
        let usedPercentage: Double

        func continues(resetsAt: TimeInterval) -> Bool {
            AllowanceForecastDescriptor.isSamePeriod(
                resetsAt: Date(timeIntervalSince1970: resetsAt),
                periodResetsAt: Date(timeIntervalSince1970: periodResetsAt)
            )
        }
    }

    private let lock = NSLock()
    private var fiveHour: Peak?
    private var sevenDay: Peak?

    init() {}

    func apply(to rateLimits: RateLimits?) -> RateLimits? {
        guard let rateLimits else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return RateLimits(
            fiveHour: Self.apply(to: rateLimits.fiveHour, peak: &fiveHour),
            sevenDay: Self.apply(to: rateLimits.sevenDay, peak: &sevenDay)
        )
    }

    /// A missing window, or one without a percentage, carries no evidence and
    /// leaves the peak as it is. A window without a reset starts a new period.
    private static func apply(to window: Window?, peak: inout Peak?) -> Window? {
        guard let window, let usedPercentage = window.usedPercentage, usedPercentage.isFinite else {
            return window
        }
        guard let resetsAt = window.resetsAt else {
            peak = nil
            return window
        }
        if let current = peak, current.continues(resetsAt: resetsAt) {
            let highest = max(current.usedPercentage, usedPercentage)
            peak = Peak(periodResetsAt: current.periodResetsAt, usedPercentage: highest)
            return Window(usedPercentage: highest, resetsAt: resetsAt, writtenAt: window.writtenAt)
        }
        peak = Peak(periodResetsAt: resetsAt, usedPercentage: usedPercentage)
        return window
    }
}
