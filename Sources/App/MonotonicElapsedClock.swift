import Foundation

/// Monotonic elapsed-time source for Smart refresh activity windows. A
/// continuous clock includes system sleep, and wall-clock edits cannot move it.
struct MonotonicElapsedClock: Sendable {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func elapsed() -> TimeInterval {
        let components = origin.duration(to: clock.now).components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1e18
    }
}
