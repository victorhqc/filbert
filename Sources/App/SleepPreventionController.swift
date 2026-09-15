import Foundation
import IOKit.pwr_mgt
import Observation

enum SleepPreventionDuration: CaseIterable, Identifiable {
    case fiveMinutes
    case tenMinutes
    case twentyMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case untilTurnedOff

    var id: Self {
        self
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .fiveMinutes:
            5 * 60
        case .tenMinutes:
            10 * 60
        case .twentyMinutes:
            20 * 60
        case .thirtyMinutes:
            30 * 60
        case .oneHour:
            60 * 60
        case .twoHours:
            2 * 60 * 60
        case .untilTurnedOff:
            nil
        }
    }
}

struct SleepPreventionAssertionID: Equatable {
    let rawValue: UInt32
}

protocol SleepPreventionPowerManaging: AnyObject {
    func createIdleDisplaySleepAssertion(reason: String) throws -> SleepPreventionAssertionID
    func releaseAssertion(_ assertionID: SleepPreventionAssertionID)
}

private final class IOKitSleepPreventionPowerManager: SleepPreventionPowerManaging {
    func createIdleDisplaySleepAssertion(reason: String) throws -> SleepPreventionAssertionID {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            throw SleepPreventionPowerError.creationFailed(result)
        }
        return SleepPreventionAssertionID(rawValue: assertionID)
    }

    func releaseAssertion(_ assertionID: SleepPreventionAssertionID) {
        IOPMAssertionRelease(IOPMAssertionID(assertionID.rawValue))
    }
}

private enum SleepPreventionPowerError: Error {
    case creationFailed(IOReturn)
}

@MainActor
protocol SleepPreventionScheduledTask: AnyObject {
    func cancel()
}

@MainActor
protocol SleepPreventionScheduling: AnyObject {
    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SleepPreventionScheduledTask
}

@MainActor
private final class RunLoopSleepPreventionScheduler: SleepPreventionScheduling {
    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SleepPreventionScheduledTask {
        RunLoopSleepPreventionScheduledTask(interval: interval, action: action)
    }
}

@MainActor
private final class RunLoopSleepPreventionScheduledTask: NSObject, SleepPreventionScheduledTask {
    private var timer: Timer?
    private let action: @MainActor () -> Void

    init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.action = action
        super.init()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func handleTimer() {
        action()
    }
}

@MainActor
enum SleepPreventionPreferences {
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    static var isVisible: Bool {
        defaults.object(forKey: Keys.isVisible) as? Bool ?? true
    }

    static func setVisible(_ isVisible: Bool) {
        defaults.set(isVisible, forKey: Keys.isVisible)
    }

    static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private enum Keys {
        static let isVisible = "sleep-prevention-visible"
    }
}

@MainActor
@Observable
final class SleepPreventionController {
    enum Session: Equatable {
        case timed(deadline: Date)
        case untilTurnedOff
    }

    private let powerManager: any SleepPreventionPowerManaging
    private let scheduler: any SleepPreventionScheduling
    private let now: () -> Date
    private var assertionID: SleepPreventionAssertionID?
    private var scheduledTask: (any SleepPreventionScheduledTask)?

    private(set) var session: Session?
    private(set) var remainingSeconds = 0
    private(set) var didFailToActivate = false
    private(set) var isFeatureVisible: Bool

    init(
        powerManager: any SleepPreventionPowerManaging = IOKitSleepPreventionPowerManager(),
        scheduler: any SleepPreventionScheduling = RunLoopSleepPreventionScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.powerManager = powerManager
        self.scheduler = scheduler
        self.now = now
        isFeatureVisible = SleepPreventionPreferences.isVisible
    }

    var isActive: Bool {
        session != nil
    }

    var isAwakeIndicatorVisible: Bool {
        isFeatureVisible && isActive
    }

    var rowTitle: String {
        switch session {
        case .none:
            String(localized: "Prevent Mac from sleeping for…")
        case .some(.untilTurnedOff):
            String(localized: "Mac won't sleep until turned off")
        case .some(.timed):
            String.localizedStringWithFormat(
                String(localized: "Mac won't sleep for %@"),
                Self.remainingTimeText(for: remainingSeconds)
            )
        }
    }

    var accessibilityValue: String {
        switch session {
        case .none:
            String(localized: "Inactive")
        case .some(.untilTurnedOff):
            String(localized: "Mac won't sleep until turned off")
        case .some(.timed):
            String.localizedStringWithFormat(
                String(localized: "Mac won't sleep for %@"),
                Self.remainingTimeText(for: remainingSeconds)
            )
        }
    }

    func start(_ duration: SleepPreventionDuration) {
        guard isFeatureVisible else { return }

        didFailToActivate = false
        guard createAssertionIfNeeded() else { return }

        scheduledTask?.cancel()
        scheduledTask = nil

        guard let interval = duration.timeInterval else {
            session = .untilTurnedOff
            remainingSeconds = 0
            return
        }

        let deadline = now().addingTimeInterval(interval)
        session = .timed(deadline: deadline)
        remainingSeconds = Self.remainingSeconds(until: deadline, now: now())
        scheduledTask = scheduler.scheduleRepeating(every: 1) { [weak self] in
            self?.reconcile()
        }
    }

    func stop() {
        scheduledTask?.cancel()
        scheduledTask = nil
        session = nil
        remainingSeconds = 0
        didFailToActivate = false

        if let assertionID {
            powerManager.releaseAssertion(assertionID)
            self.assertionID = nil
        }
    }

    func reconcile() {
        guard case let .timed(deadline) = session else { return }

        let seconds = Self.remainingSeconds(until: deadline, now: now())
        guard seconds > 0 else {
            stop()
            return
        }
        remainingSeconds = seconds
    }

    func setFeatureVisible(_ isVisible: Bool) {
        guard isFeatureVisible != isVisible else { return }

        SleepPreventionPreferences.setVisible(isVisible)
        isFeatureVisible = isVisible
        if !isVisible {
            stop()
        }
    }

    static func remainingTimeText(for remainingSeconds: Int) -> String {
        let hours = remainingSeconds / 3600
        let minutes = remainingSeconds % 3600 / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func createAssertionIfNeeded() -> Bool {
        guard assertionID == nil else { return true }

        do {
            assertionID = try powerManager.createIdleDisplaySleepAssertion(reason: "Filbert sleep prevention")
            return true
        } catch {
            didFailToActivate = true
            return false
        }
    }

    private static func remainingSeconds(until deadline: Date, now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }
}
