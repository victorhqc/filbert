@testable import App
import AppKit
import XCTest

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testInitialStatusDoesNotChangeRegistration() {
        for status in [LaunchAtLoginStatus.notRegistered, .enabled, .requiresApproval, .notFound, .unavailable] {
            let client = FakeLaunchAtLoginClient(status: status)
            let controller = LaunchAtLoginController(client: client)

            XCTAssertEqual(controller.status, status)
            XCTAssertEqual(controller.isRegistered, status == .enabled || status == .requiresApproval)
            XCTAssertEqual(controller.isAvailable, status != .unavailable)
            XCTAssertNil(controller.errorMessage)
            XCTAssertEqual(client.registerCount, 0)
            XCTAssertEqual(client.unregisterCount, 0)
        }
    }

    func testEnablingRegistersOnceAndReadsStatus() {
        for status in [LaunchAtLoginStatus.notRegistered, .notFound] {
            let client = FakeLaunchAtLoginClient(status: status)
            let controller = LaunchAtLoginController(client: client)

            controller.setRegistered(true)
            controller.setRegistered(true)

            XCTAssertEqual(client.registerCount, 1)
            XCTAssertEqual(controller.status, .enabled)
            XCTAssertTrue(controller.isRegistered)
            XCTAssertNil(controller.errorMessage)
        }
    }

    func testDisablingRemovesEnabledAndPendingRegistrations() {
        for status in [LaunchAtLoginStatus.enabled, .requiresApproval] {
            let client = FakeLaunchAtLoginClient(status: status)
            let controller = LaunchAtLoginController(client: client)

            controller.setRegistered(false)
            controller.setRegistered(false)

            XCTAssertEqual(client.unregisterCount, 1)
            XCTAssertEqual(controller.status, .notRegistered)
            XCTAssertFalse(controller.isRegistered)
            XCTAssertNil(controller.errorMessage)
        }
    }

    func testApprovalRequiredDoesNotCauseRepeatedRegistration() {
        for status in [LaunchAtLoginStatus.notRegistered, .notFound] {
            let client = FakeLaunchAtLoginClient(status: status)
            client.registrationStatus = .requiresApproval
            let controller = LaunchAtLoginController(client: client)

            controller.setRegistered(true)
            controller.setRegistered(true)
            controller.refreshStatus()

            XCTAssertEqual(client.registerCount, 1)
            XCTAssertEqual(controller.status, .requiresApproval)
            XCTAssertTrue(controller.isRegistered)
        }
    }

    func testSuccessfulOperationDoesNotAssumeRequestedState() {
        for status in [LaunchAtLoginStatus.notRegistered, .notFound] {
            let client = FakeLaunchAtLoginClient(status: status)
            client.registrationStatus = status
            let controller = LaunchAtLoginController(client: client)

            controller.setRegistered(true)
            controller.refreshStatus()
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

            XCTAssertEqual(client.registerCount, 1)
            XCTAssertEqual(controller.status, status)
            XCTAssertFalse(controller.isRegistered)
            XCTAssertTrue(controller.isAvailable)
        }
    }

    func testMissingNativeServiceRemainsAvailableWithoutAutomaticRegistration() {
        let client = FakeLaunchAtLoginClient(status: LaunchAtLoginStatus(nativeStatus: .notFound))
        let controller = LaunchAtLoginController(client: client)

        controller.refreshStatus()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(controller.status, .notFound)
        XCTAssertTrue(controller.isAvailable)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(client.registerCount, 0)
        XCTAssertEqual(client.unregisterCount, 0)
    }

    func testEnablingAnExistingRegistrationDoesNothing() {
        for status in [LaunchAtLoginStatus.enabled, .requiresApproval] {
            let client = FakeLaunchAtLoginClient(status: status)
            let controller = LaunchAtLoginController(client: client)

            controller.setRegistered(true)

            XCTAssertEqual(client.registerCount, 0)
            XCTAssertEqual(client.unregisterCount, 0)
        }
    }

    func testDisablingAnUnregisteredServiceDoesNothing() {
        for status in [LaunchAtLoginStatus.notRegistered, .notFound] {
            let client = FakeLaunchAtLoginClient(status: status)
            let controller = LaunchAtLoginController(client: client)

            controller.setRegistered(false)

            XCTAssertEqual(client.registerCount, 0)
            XCTAssertEqual(client.unregisterCount, 0)
        }
    }

    func testUnavailableServiceCannotRegisterOrUnregister() {
        let client = FakeLaunchAtLoginClient(status: .unavailable)
        let controller = LaunchAtLoginController(client: client)

        controller.setRegistered(true)
        controller.setRegistered(false)

        XCTAssertFalse(controller.isAvailable)
        XCTAssertEqual(client.registerCount, 0)
        XCTAssertEqual(client.unregisterCount, 0)
    }

    func testRefreshReflectsExternalChangesWithoutMutatingThem() {
        let client = FakeLaunchAtLoginClient(status: .enabled)
        let controller = LaunchAtLoginController(client: client)

        for status in [LaunchAtLoginStatus.requiresApproval, .notRegistered, .enabled, .notFound, .unavailable] {
            client.status = status
            controller.refreshStatus()

            XCTAssertEqual(controller.status, status)
        }
        XCTAssertEqual(client.registerCount, 0)
        XCTAssertEqual(client.unregisterCount, 0)
    }

    func testAppActivationReadsExternalStatus() {
        let client = FakeLaunchAtLoginClient(status: .enabled)
        let controller = LaunchAtLoginController(client: client)
        client.status = .requiresApproval

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertEqual(client.registerCount, 0)
    }

    func testActionReconcilesExternalStatusBeforeRegistering() {
        let client = FakeLaunchAtLoginClient(status: .notRegistered)
        let controller = LaunchAtLoginController(client: client)
        client.status = .requiresApproval

        controller.setRegistered(true)

        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertEqual(client.registerCount, 0)
    }

    func testRegistrationFailureCanBeRetried() {
        for status in [LaunchAtLoginStatus.notRegistered, .notFound] {
            let client = FakeLaunchAtLoginClient(status: status)
            client.registrationError = .failed
            client.registrationStatus = status
            let controller = LaunchAtLoginController(client: client)

            controller.setRegistered(true)

            XCTAssertEqual(controller.status, status)
            XCTAssertTrue(controller.isAvailable)
            XCTAssertNotNil(controller.errorMessage)
            client.registrationError = nil
            client.registrationStatus = .enabled

            controller.setRegistered(true)

            XCTAssertEqual(client.registerCount, 2)
            XCTAssertEqual(controller.status, .enabled)
            XCTAssertNil(controller.errorMessage)
        }
    }

    func testRemovalFailureCanBeRetried() {
        let client = FakeLaunchAtLoginClient(status: .enabled)
        client.removalError = .failed
        client.removalStatus = .enabled
        let controller = LaunchAtLoginController(client: client)

        controller.setRegistered(false)

        XCTAssertEqual(controller.status, .enabled)
        XCTAssertNotNil(controller.errorMessage)
        client.removalError = nil
        client.removalStatus = .notRegistered

        controller.setRegistered(false)

        XCTAssertEqual(client.unregisterCount, 2)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertNil(controller.errorMessage)
    }

    func testStatusIsReadEvenWhenRegistrationThrowsAfterAStateChange() {
        let client = FakeLaunchAtLoginClient(status: .notRegistered)
        client.registrationError = .failed
        client.registrationStatus = .requiresApproval
        let controller = LaunchAtLoginController(client: client)

        controller.setRegistered(true)

        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testStatusIsReadEvenWhenRemovalThrowsAfterAStateChange() {
        let client = FakeLaunchAtLoginClient(status: .enabled)
        client.removalError = .failed
        client.removalStatus = .notRegistered
        let controller = LaunchAtLoginController(client: client)

        controller.setRegistered(false)

        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testExternalStatusChangeClearsAnObsoleteError() {
        let client = FakeLaunchAtLoginClient(status: .notRegistered)
        client.registrationError = .failed
        client.registrationStatus = .notRegistered
        let controller = LaunchAtLoginController(client: client)
        controller.setRegistered(true)
        XCTAssertNotNil(controller.errorMessage)

        client.status = .enabled
        controller.refreshStatus()

        XCTAssertEqual(controller.status, .enabled)
        XCTAssertNil(controller.errorMessage)
    }

    func testSettingsActionIsDelegatedWithoutChangingRegistration() {
        let client = FakeLaunchAtLoginClient(status: .requiresApproval)
        let controller = LaunchAtLoginController(client: client)

        controller.openLoginItemsSettings()

        XCTAssertEqual(client.openSettingsCount, 1)
        XCTAssertEqual(client.registerCount, 0)
        XCTAssertEqual(client.unregisterCount, 0)
    }

    func testControllerTeardownDoesNotRemoveRegistration() {
        let client = FakeLaunchAtLoginClient(status: .enabled)
        weak var releasedController: LaunchAtLoginController?

        do {
            let controller = LaunchAtLoginController(client: client)
            releasedController = controller
            XCTAssertTrue(controller.isRegistered)
        }

        XCTAssertNil(releasedController)
        XCTAssertEqual(client.unregisterCount, 0)
    }
}

@MainActor
private final class FakeLaunchAtLoginClient: LaunchAtLoginManaging {
    enum Failure: Error {
        case failed
    }

    var status: LaunchAtLoginStatus
    var registrationStatus: LaunchAtLoginStatus = .enabled
    var removalStatus: LaunchAtLoginStatus = .notRegistered
    var registrationError: Failure?
    var removalError: Failure?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        status = registrationStatus
        if let registrationError {
            throw registrationError
        }
    }

    func unregister() throws {
        unregisterCount += 1
        status = removalStatus
        if let removalError {
            throw removalError
        }
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}
