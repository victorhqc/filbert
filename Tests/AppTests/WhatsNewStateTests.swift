@testable import App
import Foundation
import XCTest

final class WhatsNewStateTests: XCTestCase {
    private let suiteName = "filbert-whats-new-tests-\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAnUpdateAnnouncesTheRunningVersion() {
        defaults.set("0.25.0", forKey: WhatsNewState.lastSeenKey)

        let releases = makeState(running: "0.26.0").resolveLaunchAnnouncement(in: highlights)

        XCTAssertEqual(versions(releases), ["0.26.0"])
        XCTAssertEqual(lastSeen, "0.25.0")
    }

    func testSkippedVersionsAreAnnouncedNewestFirst() {
        defaults.set("0.23.0", forKey: WhatsNewState.lastSeenKey)

        let releases = makeState(running: "0.26.0").resolveLaunchAnnouncement(in: highlights)

        XCTAssertEqual(versions(releases), ["0.26.0", "0.24.0"])
    }

    func testTheAnnouncementStaysUntilItIsSeen() {
        defaults.set("0.25.0", forKey: WhatsNewState.lastSeenKey)
        _ = makeState(running: "0.26.0").resolveLaunchAnnouncement(in: highlights)

        let relaunched = makeState(running: "0.26.0")
        XCTAssertEqual(versions(relaunched.resolveLaunchAnnouncement(in: highlights)), ["0.26.0"])

        relaunched.markSeen()

        XCTAssertEqual(versions(makeState(running: "0.26.0").resolveLaunchAnnouncement(in: highlights)), [])
        XCTAssertEqual(lastSeen, "0.26.0")
    }

    func testANewInstallAnnouncesNothingAndSavesTheVersion() {
        let releases = makeState(running: "0.26.0", existingInstall: false).resolveLaunchAnnouncement(in: highlights)

        XCTAssertEqual(versions(releases), [])
        XCTAssertEqual(lastSeen, "0.26.0")
    }

    func testAnExistingInstallWithoutAValueAnnouncesOnlyTheRunningVersion() {
        let releases = makeState(running: "0.26.0", existingInstall: true).resolveLaunchAnnouncement(in: highlights)

        XCTAssertEqual(versions(releases), ["0.26.0"])
        XCTAssertNil(lastSeen)
    }

    func testVersionsWithNothingToShowAreSavedSilently() {
        defaults.set("0.26.0", forKey: WhatsNewState.lastSeenKey)

        let releases = makeState(running: "0.27.0").resolveLaunchAnnouncement(in: highlights)

        XCTAssertEqual(versions(releases), [])
        XCTAssertEqual(lastSeen, "0.27.0")
    }

    func testAnOlderRunningVersionAnnouncesNothing() {
        defaults.set("0.26.0", forKey: WhatsNewState.lastSeenKey)

        let releases = makeState(running: "0.24.0").resolveLaunchAnnouncement(in: highlights)

        XCTAssertEqual(versions(releases), [])
        XCTAssertEqual(lastSeen, "0.24.0")
    }

    func testADevelopmentBuildAnnouncesNothingAndSavesNothing() {
        defaults.set("0.23.0", forKey: WhatsNewState.lastSeenKey)

        let state = makeState(running: nil)

        XCTAssertEqual(versions(state.resolveLaunchAnnouncement(in: highlights)), [])
        state.markSeen()
        XCTAssertEqual(lastSeen, "0.23.0")
    }

    func testTheLaunchArgumentOpensTheWindow() {
        XCTAssertTrue(makeState(running: nil, arguments: ["App", WhatsNewState.showArgument]).opensOnLaunch)
        XCTAssertFalse(makeState(running: "0.26.0").opensOnLaunch)
    }

    func testTheBundleVersionMustBeAPlainRelease() {
        XCTAssertNil(WhatsNewState.bundleVersion(Bundle(for: Self.self)))
    }

    private var lastSeen: String? {
        defaults.string(forKey: WhatsNewState.lastSeenKey)
    }

    private var highlights: ReleaseHighlights {
        ReleaseHighlights(releases: [
            release("0.27.0", items: []),
            release("0.26.0", items: [item("Something new.")]),
            release("0.25.0", items: []),
            release("0.24.0", items: [item("Something older.")]),
        ])
    }

    private func makeState(
        running: String?,
        existingInstall: Bool = true,
        arguments: [String] = ["App"]
    ) -> WhatsNewState {
        WhatsNewState(
            defaults: defaults,
            runningVersion: running.flatMap(ReleaseVersion.init),
            arguments: arguments,
            hasExistingInstall: { existingInstall }
        )
    }

    private func versions(_ releases: [ReleaseHighlights.Release]) -> [String] {
        releases.map(\.version.description)
    }

    private func release(_ version: String, items: [ReleaseHighlight]) -> ReleaseHighlights.Release {
        ReleaseHighlights.Release(version: ReleaseVersion(version)!, items: items)
    }

    private func item(_ english: String) -> ReleaseHighlight {
        ReleaseHighlight(kind: .feature, text: ["en": english])
    }
}
