@testable import App
import Foundation
import Sparkle
import XCTest

@MainActor
final class UpdateCoordinatorTests: XCTestCase {
    func testDevelopmentBundleIsNotEligible() {
        XCTAssertFalse(UpdateEligibility.isEligible(bundle: .main))
    }

    func testInstalledBundleWithUpdaterConfigurationIsEligible() throws {
        let bundle = try makeBundle(
            version: "1.2.3",
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )

        XCTAssertTrue(UpdateEligibility.isEligible(bundle: bundle))
    }

    func testPlaceholderPublicKeyDisablesUpdater() throws {
        let bundle = try makeBundle(
            version: "1.2.3",
            publicKey: "@SPARKLE_PUBLIC_ED_KEY@"
        )

        XCTAssertFalse(UpdateEligibility.isEligible(bundle: bundle))
    }

    func testNonCanonicalFeedDisablesUpdater() throws {
        let bundle = try makeBundle(
            version: "1.2.3",
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            feedURL: "https://example.com/appcast.xml"
        )

        XCTAssertFalse(UpdateEligibility.isEligible(bundle: bundle))
    }

    func testInvalidVersionsDisableUpdater() {
        XCTAssertFalse(UpdateEligibility.isReleaseVersion("@VERSION@"))
        XCTAssertFalse(UpdateEligibility.isReleaseVersion("0.0.0"))
        XCTAssertTrue(UpdateEligibility.isReleaseVersion("1.2.3"))
    }

    func testCoordinatorIsInactiveForDevelopmentBundle() {
        let coordinator = UpdateCoordinator(bundle: .main)

        XCTAssertFalse(coordinator.isAvailable)
        XCTAssertFalse(coordinator.canCheckForUpdates)
        XCTAssertFalse(coordinator.automaticallyChecksForUpdates)
    }

    func testGateRefusesOnlyScheduledChecks() {
        XCTAssertFalse(ScheduledCheckGate.allows(.updatesInBackground))
        XCTAssertTrue(ScheduledCheckGate.allows(.updateInformation))
        XCTAssertTrue(ScheduledCheckGate.allows(.updates))
    }

    func testCoordinatorImplementsSparkleGateSelectors() {
        let coordinator = UpdateCoordinator(bundle: .main)

        for selector in [
            "updater:mayPerformUpdateCheck:error:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:",
            "updater:didAbortWithError:",
        ] {
            XCTAssertTrue(coordinator.responds(to: NSSelectorFromString(selector)), selector)
        }
    }

    func testRefusalStartsInformationCheckOnlyAfterScheduledCheck() {
        let otherError = NSError(domain: SUSparkleErrorDomain, code: 1001)

        XCTAssertTrue(ScheduledCheckGate.startsInformationCheck(
            after: .updatesInBackground,
            error: ScheduledCheckGate.refusal
        ))
        XCTAssertFalse(ScheduledCheckGate.startsInformationCheck(after: .updatesInBackground, error: nil))
        XCTAssertFalse(ScheduledCheckGate.startsInformationCheck(after: .updatesInBackground, error: otherError))
        XCTAssertFalse(ScheduledCheckGate.startsInformationCheck(after: .updateInformation, error: nil))
        XCTAssertFalse(ScheduledCheckGate.startsInformationCheck(after: .updates, error: nil))
    }

    func testRefusalIsRecognizedAfterBeingThrown() {
        let thrown: any Error
        do {
            try throwRefusal()
            return XCTFail("Expected the refusal to be thrown")
        } catch {
            thrown = error
        }

        XCTAssertTrue(ScheduledCheckGate.isRefusal(thrown))
        XCTAssertFalse(ScheduledCheckGate.isRefusal(nil))
    }

    func testRefusalNeverReachesPopoverPhase() {
        let coordinator = UpdateCoordinator(bundle: .main)
        var installCount = 0
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))
        coordinator.recordReadyToInstall(version: "0.14.0") { installCount += 1 }

        coordinator.recordUpdateAbort(ScheduledCheckGate.refusal)
        coordinator.installNow()

        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(coordinator.updatePhase, .installing(version: "0.14.0"))
    }

    func testOtherAbortStillFallsBackToAvailable() {
        let coordinator = UpdateCoordinator(bundle: .main)
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))
        coordinator.recordUpdateProgress(.downloadStarted)

        coordinator.recordUpdateAbort(NSError(domain: SUSparkleErrorDomain, code: 2001))

        XCTAssertEqual(coordinator.updatePhase, .available(version: "0.14.0"))
    }

    func testPackagedAppNeverDownloadsUpdatesInBackground() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../packaging/Info.plist")
            .standardizedFileURL
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let info = try XCTUnwrap(plist as? [String: Any])

        XCTAssertEqual(info[UpdateConfiguration.allowsAutomaticUpdatesKey] as? Bool, false)
        XCTAssertNil(info["SUAutomaticallyUpdate"])
        XCTAssertEqual(info[UpdateConfiguration.automaticChecksKey] as? Bool, true)
    }

    func testAvailableUpdateAppearsInPopover() {
        let coordinator = UpdateCoordinator(bundle: .main)

        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))

        XCTAssertEqual(coordinator.popoverUpdate?.phase, .available(version: "0.14.0"))
    }

    func testAvailableUpdateOffersActionOnlyWhenUpdaterCanCheck() {
        let ready = PopoverUpdate(phase: .available(version: "0.14.0"), canCheckForUpdates: true)
        let busy = PopoverUpdate(phase: .available(version: "0.14.0"), canCheckForUpdates: false)

        XCTAssertEqual(ready?.action, .update)
        XCTAssertEqual(ready?.showsProgress, false)
        XCTAssertNil(busy?.action)
        XCTAssertEqual(busy?.showsProgress, true)
    }

    func testBackgroundWorkShowsProgressWithoutAction() {
        for phase in [
            UpdatePhase.downloading(version: "0.14.0"),
            .preparing(version: "0.14.0"),
            .installing(version: "0.14.0"),
        ] {
            let update = PopoverUpdate(phase: phase, canCheckForUpdates: true)

            XCTAssertNil(update?.action, "\(phase)")
            XCTAssertEqual(update?.showsProgress, true, "\(phase)")
        }
    }

    func testReadyUpdateOffersRestartEvenWhileSessionIsHeld() {
        let update = PopoverUpdate(phase: .readyToInstall(version: "0.14.0"), canCheckForUpdates: false)

        XCTAssertEqual(update?.action, .restartToUpdate)
        XCTAssertEqual(update?.showsProgress, false)
    }

    func testPopoverUpdateIsAbsentWithoutPhase() {
        XCTAssertNil(PopoverUpdate(phase: nil, canCheckForUpdates: true))
    }

    func testNoUpdateClearsPopoverAvailability() {
        let coordinator = UpdateCoordinator(bundle: .main)
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))

        coordinator.recordUpdateCheckResult(.noUpdate)

        XCTAssertNil(coordinator.popoverUpdate)
    }

    func testFailedCheckRetainsKnownUpdate() {
        let coordinator = UpdateCoordinator(bundle: .main)
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))

        coordinator.recordUpdateCheckResult(.failed)

        XCTAssertEqual(coordinator.updatePhase, .available(version: "0.14.0"))
    }

    func testDownloadAdvancesThroughPhases() {
        let coordinator = UpdateCoordinator(bundle: .main)
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))

        coordinator.recordUpdateProgress(.downloadStarted)
        XCTAssertEqual(coordinator.updatePhase, .downloading(version: "0.14.0"))

        coordinator.recordUpdateProgress(.preparationStarted)
        XCTAssertEqual(coordinator.updatePhase, .preparing(version: "0.14.0"))

        coordinator.recordReadyToInstall(version: "0.14.0") {}
        XCTAssertEqual(coordinator.updatePhase, .readyToInstall(version: "0.14.0"))
    }

    func testProgressWithoutKnownUpdateIsIgnored() {
        let coordinator = UpdateCoordinator(bundle: .main)

        coordinator.recordUpdateProgress(.downloadStarted)

        XCTAssertNil(coordinator.updatePhase)
    }

    func testInterruptedDownloadFallsBackToAvailable() {
        let coordinator = UpdateCoordinator(bundle: .main)
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))
        coordinator.recordUpdateProgress(.downloadStarted)

        coordinator.recordUpdateProgress(.interrupted)

        XCTAssertEqual(coordinator.updatePhase, .available(version: "0.14.0"))
    }

    func testFailureDuringPreparationFallsBackToAvailable() {
        let coordinator = UpdateCoordinator(bundle: .main)
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))
        coordinator.recordUpdateProgress(.preparationStarted)

        coordinator.recordUpdateCheckResult(.failed)

        XCTAssertEqual(coordinator.updatePhase, .available(version: "0.14.0"))
    }

    func testInstallNowInvokesHandlerOnce() {
        let coordinator = UpdateCoordinator(bundle: .main)
        var installCount = 0
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))
        coordinator.recordReadyToInstall(version: "0.14.0") { installCount += 1 }

        coordinator.installNow()
        coordinator.installNow()

        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(coordinator.updatePhase, .installing(version: "0.14.0"))
    }

    func testInstallNowDoesNothingBeforeUpdateIsReady() {
        let coordinator = UpdateCoordinator(bundle: .main)
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))
        coordinator.recordUpdateProgress(.downloadStarted)

        coordinator.installNow()

        XCTAssertEqual(coordinator.updatePhase, .downloading(version: "0.14.0"))
    }

    func testInterruptionDiscardsPendingInstallHandler() {
        let coordinator = UpdateCoordinator(bundle: .main)
        var installCount = 0
        coordinator.recordUpdateCheckResult(.updateAvailable(version: "0.14.0"))
        coordinator.recordReadyToInstall(version: "0.14.0") { installCount += 1 }

        coordinator.recordUpdateProgress(.interrupted)
        coordinator.installNow()

        XCTAssertEqual(installCount, 0)
        XCTAssertEqual(coordinator.updatePhase, .available(version: "0.14.0"))
    }

    func testConfigurationUsesCanonicalFeedAndFourHourInterval() {
        XCTAssertEqual(
            UpdateConfiguration.feedURL,
            "https://victorhqc.github.io/filbert/appcast.xml"
        )
        XCTAssertEqual(UpdateConfiguration.defaultCheckInterval, 4 * 60 * 60)
    }

    private func throwRefusal() throws {
        throw ScheduledCheckGate.refusal
    }

    private func makeBundle(
        version: String,
        publicKey: String,
        feedURL: String = UpdateConfiguration.feedURL
    ) throws -> Bundle {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Filbert.app")
        let contentsURL = rootURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.victorhqc.filbert.tests",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version,
            "SUPublicEDKey": publicKey,
            "SUFeedURL": feedURL,
        ]
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        try (info as NSDictionary).write(to: infoURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        guard let bundle = Bundle(url: rootURL) else {
            throw NSError(domain: "UpdateCoordinatorTests", code: 1)
        }
        return bundle
    }
}
