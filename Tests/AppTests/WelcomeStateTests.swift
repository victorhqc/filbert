@testable import App
import Foundation
import XCTest

final class WelcomeStateTests: XCTestCase {
    private let suiteName = "filbert-welcome-tests-\(UUID().uuidString)"
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

    func testAFreshInstallShowsTheWelcomeWindow() {
        XCTAssertTrue(makeState(existingInstall: false).shouldShowOnLaunch)
    }

    func testAnExistingInstallDoesNotShowIt() {
        XCTAssertFalse(makeState(existingInstall: true).shouldShowOnLaunch)
    }

    func testACompletedWelcomeDoesNotShowAgain() {
        makeState(existingInstall: false).markCompleted()

        let relaunched = makeState(existingInstall: false)

        XCTAssertTrue(relaunched.isCompleted)
        XCTAssertFalse(relaunched.shouldShowOnLaunch)
    }

    func testTheLaunchArgumentShowsItWithoutResettingCompletion() {
        makeState(existingInstall: true).markCompleted()

        let state = makeState(existingInstall: true, arguments: ["App", WelcomeState.showArgument])

        XCTAssertTrue(state.shouldShowOnLaunch)
        XCTAssertTrue(state.isCompleted)
    }

    private func makeState(existingInstall: Bool, arguments: [String] = ["App"]) -> WelcomeState {
        WelcomeState(defaults: defaults, arguments: arguments, hasExistingInstall: { existingInstall })
    }
}
