import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

final class CodexHooksStatusTextTests: XCTestCase {
    private var directory: URL!
    private var installer: CodexHooksInstaller!

    override func setUpWithError() throws {
        DisplayLanguage.selectedLanguageCode = "en"
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        installer = CodexHooksInstaller(
            hooksURL: directory.appendingPathComponent(".codex/hooks.json"),
            signalURL: directory.appendingPathComponent("cache/filbert/codex-activity")
        )
    }

    override func tearDownWithError() throws {
        DisplayLanguage.selectedLanguageCode = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testNotInstalledExplainsWhatInstallAdds() {
        guard case let .notInstalled(text) = installer.status() else {
            return XCTFail("Expected notInstalled")
        }
        XCTAssertTrue(text?.resolved.contains("~/.codex/hooks.json") == true)
    }

    func testTheNextStepsListTheApprovalAndAFirstPrompt() throws {
        try installer.install()

        guard case let .awaitingFirstSignal(text) = installer.status() else {
            return XCTFail("Expected awaitingFirstSignal")
        }
        let lines = text?.resolved.components(separatedBy: "\n") ?? []
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines.dropFirst().first?.hasPrefix("1. ") == true)
        XCTAssertTrue(lines.dropFirst(2).first?.hasPrefix("2. ") == true)
    }
}
