@testable import ClaudeCodeProvider
import XCTest

final class ClaudeCodeLocatorTests: XCTestCase {
    // MARK: - resolve() returns injected path

    func testResolve_returnsInjectedPath() {
        let locator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude")
        XCTAssertEqual(locator.resolve(), "/usr/local/bin/claude")
    }

    // MARK: - resolve() returns nil when binary not found (injected)

    func testResolve_returnsNil_whenInjectedAsNotFound() {
        let locator = ClaudeCodeLocator(injectedPath: nil)
        XCTAssertNil(locator.resolve())
    }

    // MARK: - real resolve runs without crashing

    func testResolve_realResolution_doesNotThrow() {
        // Production initializer — may or may not find claude depending on
        // the machine, but must not crash.
        let locator = ClaudeCodeLocator()
        _ = locator.resolve()
    }
}
