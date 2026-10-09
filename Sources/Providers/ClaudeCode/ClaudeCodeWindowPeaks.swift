import Core
import Foundation

/// The statusline reports one point less than `/usage` for the same window.
final class ClaudeCodeWindowPeaks: @unchecked Sendable {
    private struct Peak {
        // Not the latest reset: small moves would add up past the tolerance.
        let firstResetsAt: TimeInterval
        let usedPercentage: Double

        func continues(resetsAt: TimeInterval) -> Bool {
            AllowanceForecastDescriptor.isSamePeriod(
                resetsAt: Date(timeIntervalSince1970: resetsAt),
                periodResetsAt: Date(timeIntervalSince1970: firstResetsAt)
            )
        }
    }

    private let lock = NSLock()
    private var fiveHour: Peak?
    private var sevenDay: Peak?

    init() {}

    func peaked(_ rateLimits: RateLimits?) -> RateLimits? {
        guard let rateLimits else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return RateLimits(
            fiveHour: Self.peaked(rateLimits.fiveHour, remembering: &fiveHour),
            sevenDay: Self.peaked(rateLimits.sevenDay, remembering: &sevenDay)
        )
    }

    private static func peaked(_ window: Window?, remembering peak: inout Peak?) -> Window? {
        // The statusline writes no windows before its first API response.
        guard let window, let usedPercentage = window.usedPercentage, usedPercentage.isFinite else {
            return window
        }
        guard let resetsAt = window.resetsAt else {
            peak = nil
            return window
        }
        if let current = peak, current.continues(resetsAt: resetsAt) {
            let highest = max(current.usedPercentage, usedPercentage)
            peak = Peak(firstResetsAt: current.firstResetsAt, usedPercentage: highest)
            return Window(usedPercentage: highest, resetsAt: resetsAt, writtenAt: window.writtenAt)
        }
        peak = Peak(firstResetsAt: resetsAt, usedPercentage: usedPercentage)
        return window
    }
}
