@testable import ClaudeCodeProvider
import XCTest

final class ClaudeCodeSpawnArgumentsTests: XCTestCase {
    func testSpawnArguments_pinDefaultViewModeAndKeepVariadicToolsBeforeAFlag() throws {
        let arguments = ClaudeCodeRefresher.spawnArguments
        let settingsIndex = try XCTUnwrap(arguments.firstIndex(of: "--settings"))
        let toolsIndex = try XCTUnwrap(arguments.firstIndex(of: "--tools"))

        let settings = try JSONDecoder().decode(
            [String: String].self,
            from: Data(arguments[settingsIndex + 1].utf8)
        )
        XCTAssertEqual(settings, ["viewMode": "default"])
        XCTAssertLessThan(settingsIndex, toolsIndex)
        XCTAssertEqual(arguments[toolsIndex + 1], "")
        XCTAssertTrue(arguments[toolsIndex + 2].hasPrefix("--"))
        XCTAssertEqual(Array(arguments.suffix(2)), ["-p", "/usage"])
    }
}
