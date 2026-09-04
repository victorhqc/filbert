@testable import App
import Foundation
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
        XCTAssertFalse(coordinator.automaticallyDownloadsUpdates)
    }

    func testConfigurationUsesCanonicalFeedAndFourHourInterval() {
        XCTAssertEqual(
            UpdateConfiguration.feedURL,
            "https://victorhqc.github.io/filbert/appcast.xml"
        )
        XCTAssertEqual(UpdateConfiguration.defaultCheckInterval, 4 * 60 * 60)
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
