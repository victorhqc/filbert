@testable import App
import Foundation
import XCTest

@MainActor
final class SleepPreventionControllerTests: XCTestCase {
    private let suiteName = "filbert.tests.sleep-prevention"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        SleepPreventionPreferences.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        SleepPreventionPreferences.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testDurationOptionsContainEveryRequestedChoice() {
        XCTAssertEqual(
            SleepPreventionDuration.allCases,
            [.fiveMinutes, .tenMinutes, .twentyMinutes, .thirtyMinutes, .oneHour, .twoHours, .untilTurnedOff]
        )
    }

    func testTimedDurationsSetTheExpectedDeadline() {
        let startingDate = Date(timeIntervalSince1970: 1000)

        for duration in SleepPreventionDuration.allCases where duration.timeInterval != nil {
            let powerManager = FakePowerManager()
            let scheduler = FakeScheduler()
            let controller = SleepPreventionController(
                powerManager: powerManager,
                scheduler: scheduler,
                now: { startingDate }
            )

            controller.start(duration)

            guard case let .timed(deadline) = controller.session,
                  let interval = duration.timeInterval
            else {
                return XCTFail("Expected a timed session for \(duration)")
            }
            XCTAssertEqual(deadline, startingDate.addingTimeInterval(interval))
            XCTAssertEqual(controller.remainingSeconds, Int(interval))
            XCTAssertEqual(powerManager.createdReasons, ["Filbert sleep prevention"])
            XCTAssertEqual(scheduler.tasks.count, 1)
            controller.stop()
        }
    }

    func testUntilTurnedOffCreatesAnIndefiniteSessionWithoutATimer() {
        let powerManager = FakePowerManager()
        let scheduler = FakeScheduler()
        let controller = SleepPreventionController(
            powerManager: powerManager,
            scheduler: scheduler,
            now: Date.init
        )

        controller.start(.untilTurnedOff)

        XCTAssertEqual(controller.session, .untilTurnedOff)
        XCTAssertEqual(controller.remainingSeconds, 0)
        XCTAssertEqual(powerManager.createdReasons, ["Filbert sleep prevention"])
        XCTAssertTrue(scheduler.tasks.isEmpty)
    }

    func testReplacingADurationKeepsTheExistingAssertion() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        let powerManager = FakePowerManager()
        let scheduler = FakeScheduler()
        let controller = SleepPreventionController(
            powerManager: powerManager,
            scheduler: scheduler,
            now: { currentDate }
        )

        controller.start(.fiveMinutes)
        let firstTask = try? XCTUnwrap(scheduler.tasks.first)
        currentDate.addTimeInterval(10)
        controller.start(.oneHour)

        XCTAssertEqual(powerManager.createdReasons.count, 1)
        XCTAssertTrue(firstTask?.isCancelled == true)
        XCTAssertEqual(scheduler.tasks.count, 2)
        XCTAssertEqual(controller.remainingSeconds, 3600)
        XCTAssertTrue(powerManager.releasedIDs.isEmpty)
    }

    func testStopReleasesTheAssertionExactlyOnce() {
        let powerManager = FakePowerManager()
        let controller = SleepPreventionController(
            powerManager: powerManager,
            scheduler: FakeScheduler(),
            now: Date.init
        )

        controller.start(.fiveMinutes)
        controller.stop()
        controller.stop()

        XCTAssertEqual(powerManager.releasedIDs, [1])
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.remainingSeconds, 0)
    }

    func testExpiryReleasesTheAssertionWhenTheScheduledTickFires() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        let powerManager = FakePowerManager()
        let scheduler = FakeScheduler()
        let controller = SleepPreventionController(
            powerManager: powerManager,
            scheduler: scheduler,
            now: { currentDate }
        )

        controller.start(.fiveMinutes)
        currentDate.addTimeInterval(300)
        scheduler.fireAll()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(powerManager.releasedIDs, [1])
        XCTAssertTrue(scheduler.tasks[0].isCancelled)
    }

    func testReconcileEndsASessionThatExpiredWhileTheMacWasSleeping() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        let powerManager = FakePowerManager()
        let controller = SleepPreventionController(
            powerManager: powerManager,
            scheduler: FakeScheduler(),
            now: { currentDate }
        )

        controller.start(.fiveMinutes)
        currentDate.addTimeInterval(301)
        controller.reconcile()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(powerManager.releasedIDs, [1])
    }

    func testCreationFailureLeavesTheControllerInactive() {
        let powerManager = FakePowerManager(shouldFailToCreate: true)
        let controller = SleepPreventionController(
            powerManager: powerManager,
            scheduler: FakeScheduler(),
            now: Date.init
        )

        controller.start(.fiveMinutes)

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.didFailToActivate)
        XCTAssertTrue(powerManager.releasedIDs.isEmpty)
    }

    func testVisibilityDefaultsToOnAndPersists() {
        XCTAssertTrue(SleepPreventionPreferences.isVisible)

        let controller = SleepPreventionController(
            powerManager: FakePowerManager(),
            scheduler: FakeScheduler(),
            now: Date.init
        )
        controller.setFeatureVisible(false)

        XCTAssertFalse(SleepPreventionPreferences.isVisible)
        XCTAssertFalse(
            SleepPreventionController(
                powerManager: FakePowerManager(),
                scheduler: FakeScheduler(),
                now: Date.init
            ).isFeatureVisible
        )
    }

    func testDisablingTheFeatureStopsAnActiveSession() {
        let powerManager = FakePowerManager()
        let controller = SleepPreventionController(
            powerManager: powerManager,
            scheduler: FakeScheduler(),
            now: Date.init
        )

        controller.start(.untilTurnedOff)
        controller.setFeatureVisible(false)

        XCTAssertFalse(controller.isFeatureVisible)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isAwakeIndicatorVisible)
        XCTAssertEqual(powerManager.releasedIDs, [1])

        controller.setFeatureVisible(true)

        XCTAssertTrue(controller.isFeatureVisible)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isAwakeIndicatorVisible)
    }

    func testRemainingTimeFormattingUsesMinutesBelowOneHourAndHoursOtherwise() {
        XCTAssertEqual(SleepPreventionController.remainingTimeText(for: 59), "0:59")
        XCTAssertEqual(SleepPreventionController.remainingTimeText(for: 3599), "59:59")
        XCTAssertEqual(SleepPreventionController.remainingTimeText(for: 3600), "1:00:00")
        XCTAssertEqual(SleepPreventionController.remainingTimeText(for: 7205), "2:00:05")
    }

    func testDurationMenuTitleKeepsTheTimerInsideTheMenu() {
        let controller = SleepPreventionController(
            powerManager: FakePowerManager(),
            scheduler: FakeScheduler(),
            now: Date.init
        )

        XCTAssertEqual(controller.durationMenuTitle, "for…")

        controller.start(.fiveMinutes)

        XCTAssertEqual(controller.durationMenuTitle, "for 5:00")

        controller.start(.untilTurnedOff)

        XCTAssertEqual(controller.durationMenuTitle, "Until turned off")
    }
}

private final class FakePowerManager: SleepPreventionPowerManaging {
    private let shouldFailToCreate: Bool
    private var nextID: UInt32 = 1

    private(set) var createdReasons: [String] = []
    private(set) var releasedIDs: [UInt32] = []

    init(shouldFailToCreate: Bool = false) {
        self.shouldFailToCreate = shouldFailToCreate
    }

    func createIdleDisplaySleepAssertion(reason: String) throws -> SleepPreventionAssertionID {
        if shouldFailToCreate {
            throw FakePowerManagerError.creationFailed
        }
        createdReasons.append(reason)
        defer { nextID += 1 }
        return SleepPreventionAssertionID(rawValue: nextID)
    }

    func releaseAssertion(_ assertionID: SleepPreventionAssertionID) {
        releasedIDs.append(assertionID.rawValue)
    }
}

private enum FakePowerManagerError: Error {
    case creationFailed
}

@MainActor
private final class FakeScheduler: SleepPreventionScheduling {
    private(set) var tasks: [FakeScheduledTask] = []

    func scheduleRepeating(
        every _: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SleepPreventionScheduledTask {
        let task = FakeScheduledTask(action: action)
        tasks.append(task)
        return task
    }

    func fireAll() {
        tasks.forEach { $0.fire() }
    }
}

@MainActor
private final class FakeScheduledTask: SleepPreventionScheduledTask {
    private let action: @MainActor () -> Void
    private(set) var isCancelled = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func fire() {
        guard !isCancelled else { return }
        action()
    }
}
