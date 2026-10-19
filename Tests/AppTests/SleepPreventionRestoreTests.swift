@testable import App
import Foundation
import XCTest

@MainActor
final class SleepPreventionRestoreTests: XCTestCase {
    private let suiteName = "filbert.tests.sleep-prevention-restore"
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

    func testRememberingUntilTurnedOffDefaultsToOffAndPersists() {
        XCTAssertFalse(SleepPreventionPreferences.remembersUntilTurnedOff)
        XCTAssertFalse(makeController().remembersUntilTurnedOff)

        makeController().setRemembersUntilTurnedOff(true)

        XCTAssertTrue(SleepPreventionPreferences.remembersUntilTurnedOff)
        XCTAssertTrue(makeController().remembersUntilTurnedOff)
    }

    func testRelaunchRestoresUntilTurnedOffWhenRemembered() {
        let controller = makeController()
        controller.setRemembersUntilTurnedOff(true)
        controller.start(.untilTurnedOff)

        let powerManager = FakePowerManager()
        let relaunched = makeController(powerManager: powerManager)

        XCTAssertEqual(relaunched.session, .untilTurnedOff)
        XCTAssertTrue(relaunched.isAwakeIndicatorVisible)
        XCTAssertEqual(powerManager.createdReasons, ["Filbert sleep prevention"])
    }

    func testTurnOffIsRememberedAsOffUntilUntilTurnedOffIsChosenAgain() {
        let controller = makeController()
        controller.setRemembersUntilTurnedOff(true)
        controller.start(.untilTurnedOff)
        controller.stop()

        let relaunched = makeController()

        XCTAssertTrue(relaunched.remembersUntilTurnedOff)
        XCTAssertFalse(relaunched.isActive)

        relaunched.start(.untilTurnedOff)

        XCTAssertEqual(makeController().session, .untilTurnedOff)
    }

    func testTimedDurationsAreNeverRestored() {
        let controller = makeController()
        controller.setRemembersUntilTurnedOff(true)
        controller.start(.tenMinutes)

        XCTAssertFalse(makeController().isActive)

        let switched = makeController()
        switched.start(.untilTurnedOff)
        switched.start(.tenMinutes)

        XCTAssertFalse(makeController().isActive)
    }

    func testNothingIsRestoredWhenRememberingIsOff() {
        makeController().start(.untilTurnedOff)

        let relaunched = makeController()

        XCTAssertFalse(relaunched.isActive)

        relaunched.setRemembersUntilTurnedOff(true)

        XCTAssertFalse(makeController().isActive)
    }

    func testNothingIsRestoredWhileKeepAwakeIsHidden() {
        let controller = makeController()
        controller.setRemembersUntilTurnedOff(true)
        controller.start(.untilTurnedOff)
        SleepPreventionPreferences.setVisible(false)

        let powerManager = FakePowerManager()
        let relaunched = makeController(powerManager: powerManager)

        XCTAssertFalse(relaunched.isActive)
        XCTAssertTrue(relaunched.remembersUntilTurnedOff)
        XCTAssertTrue(powerManager.createdReasons.isEmpty)
    }

    func testTurningOnRememberingDuringASessionAppliesToThatSession() {
        let controller = makeController()
        controller.start(.untilTurnedOff)
        controller.setRemembersUntilTurnedOff(true)

        XCTAssertEqual(makeController().session, .untilTurnedOff)
    }

    func testFailedRestoreKeepsTheSavedSessionForTheNextLaunch() {
        let controller = makeController()
        controller.setRemembersUntilTurnedOff(true)
        controller.start(.untilTurnedOff)

        let failed = makeController(powerManager: FakePowerManager(shouldFailToCreate: true))

        XCTAssertFalse(failed.isActive)
        XCTAssertTrue(failed.didFailToActivate)
        XCTAssertEqual(makeController().session, .untilTurnedOff)
    }

    private func makeController(
        powerManager: FakePowerManager = FakePowerManager()
    ) -> SleepPreventionController {
        SleepPreventionController(
            powerManager: powerManager,
            scheduler: FakeScheduler(),
            now: Date.init
        )
    }
}
