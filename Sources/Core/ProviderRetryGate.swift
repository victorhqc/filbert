import Foundation

/// Runtime retry state a provider records from a live server response. Static
/// characteristics describe what a provider may cost; only a response knows
/// when the server will accept the next request, so that deadline travels here
/// instead of through static metadata.
public final class ProviderRetryGate: @unchecked Sendable {
    private let lock = NSLock()
    private let now: @Sendable () -> TimeInterval
    private var notBefore: TimeInterval?

    public init(now: (@Sendable () -> TimeInterval)? = nil) {
        self.now = now ?? ProviderRetryGate.monotonicElapsed()
    }

    /// A shorter deadline never replaces a longer one already in effect.
    public func record(retryAfter: TimeInterval) {
        guard retryAfter > 0, retryAfter.isFinite else { return }
        lock.lock()
        defer { lock.unlock() }
        let deadline = now() + retryAfter
        if let notBefore, notBefore >= deadline {
            return
        }
        notBefore = deadline
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        notBefore = nil
    }

    /// Seconds until the gate opens; zero when no deadline is active.
    public var remaining: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let notBefore else { return 0 }
        return max(0, notBefore - now())
    }

    private static func monotonicElapsed() -> @Sendable () -> TimeInterval {
        let origin = ContinuousClock.now
        return {
            let components = origin.duration(to: ContinuousClock.now).components
            return TimeInterval(components.seconds)
                + TimeInterval(components.attoseconds) / 1e18
        }
    }
}
