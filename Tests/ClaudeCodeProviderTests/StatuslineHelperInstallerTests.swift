@testable import ClaudeCodeProvider
import XCTest

final class StatuslineHelperInstallerTests: XCTestCase {
    private var tmpDir: URL!
    private var settingsURL: URL!
    private var helperURL: URL!
    private var cacheURL: URL!
    private var installer: StatuslineHelperInstaller!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-installer-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true
        )
        settingsURL = tmpDir.appendingPathComponent("settings.json")
        helperURL = tmpDir.appendingPathComponent("ai-usage-statusline")
        cacheURL = tmpDir.appendingPathComponent("claude-code.json")
        installer = StatuslineHelperInstaller(
            settingsURL: settingsURL,
            helperDestURL: helperURL,
            cacheURL: cacheURL
        )
    }

    override func tearDown() {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        tmpDir = nil
        settingsURL = nil
        helperURL = nil
        cacheURL = nil
        installer = nil
        super.tearDown()
    }

    // MARK: - isHelperInstalled (providers 02 AC3)

    func testIsHelperInstalled_trueWhenExecutableExists() {
        // Create a dummy executable at the helper path.
        try? "#!/bin/sh\necho ok".write(to: helperURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )
        XCTAssertTrue(installer.isHelperInstalled())
    }

    func testIsHelperInstalled_falseWhenFileAbsent() {
        XCTAssertFalse(installer.isHelperInstalled())
    }

    func testIsHelperInstalled_falseWhenNotExecutable() {
        try? "not executable".write(to: helperURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(installer.isHelperInstalled())
    }

    // MARK: - AC8: install with no prior statusLine

    func testInstall_setsStatusLine_whenNoPriorSettings() throws {
        try createHelperBinary()
        try installer.installSettingsOnly()

        let settings = try readSettingsJSON()
        let statusLine = settings["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, helperURL.path)
        // Claude Code requires `type: "command"` to invoke the statusLine.
        XCTAssertEqual(statusLine?["type"] as? String, "command")
    }

    func testInstall_setsStatusLine_whenSettingsHasOtherKeys() throws {
        try writeSettingsJSON(["otherKey": "value"])
        try createHelperBinary()
        try installer.installSettingsOnly()

        let settings = try readSettingsJSON()
        XCTAssertEqual(settings["otherKey"] as? String, "value")
        let statusLine = settings["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, helperURL.path)
        XCTAssertEqual(statusLine?["type"] as? String, "command")
    }

    // MARK: - AC8: install preserves existing statusLine sibling keys

    func testInstall_preservesStatusLineSiblingKeys() throws {
        // A user may have `padding` or `refreshInterval` configured alongside
        // their `command`. Install must not drop them.
        try writeSettingsJSON([
            "statusLine": [
                "command": "ccstatusline",
                "padding": 2,
                "refreshInterval": 5,
            ],
        ])
        try createHelperBinary()
        try installer.installSettingsOnly()

        let settings = try readSettingsJSON()
        let statusLine = settings["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["padding"] as? Int, 2)
        XCTAssertEqual(statusLine?["refreshInterval"] as? Int, 5)
        XCTAssertEqual(statusLine?["type"] as? String, "command")
        // Command is now chained, but the original must still be present.
        let command = statusLine?["command"] as? String ?? ""
        XCTAssertTrue(command.contains("ccstatusline"))
        XCTAssertTrue(command.contains(helperURL.path))
    }

    func testInstall_normalizesBareStringStatusLine_toObjectType() throws {
        // Claude Code accepts a bare string for statusLine, but our installer
        // should normalize it to the documented object form with `type`.
        try writeSettingsJSON(["statusLine": "original-cmd"])
        try createHelperBinary()
        try installer.installSettingsOnly()

        let settings = try readSettingsJSON()
        let statusLine = settings["statusLine"] as? [String: Any]
        XCTAssertNotNil(statusLine, "statusLine should be an object after install")
        XCTAssertEqual(statusLine?["type"] as? String, "command")
    }

    // MARK: - AC8: install chains existing statusLine.command

    func testInstall_chainsExistingStringCommand() throws {
        try writeSettingsJSON(["statusLine": "original-cmd"])
        try createHelperBinary()
        try installer.installSettingsOnly()

        let settings = try readSettingsJSON()
        let command = extractCommand(from: settings)
        XCTAssertTrue(command?.contains("original-cmd") ?? false)
        XCTAssertTrue(command?.contains(helperURL.path) ?? false)
    }

    func testInstall_chainsExistingObjectCommand() throws {
        try writeSettingsJSON(["statusLine": ["command": "ccstatusline"]])
        try createHelperBinary()
        try installer.installSettingsOnly()

        let settings = try readSettingsJSON()
        let command = extractCommand(from: settings)
        XCTAssertTrue(command?.contains("ccstatusline") ?? false)
        XCTAssertTrue(command?.contains(helperURL.path) ?? false)
    }

    // MARK: - AC8: reinstall replaces in place (no double-wrapping)

    func testInstall_replacesExistingChain_whenAlreadyInstalled() throws {
        // First install
        try writeSettingsJSON(["statusLine": "original-cmd"])
        try createHelperBinary()
        try installer.installSettingsOnly()

        let firstCommand = try extractCommand(from: readSettingsJSON()) ?? ""

        // Second install (reinstall)
        try installer.installSettingsOnly()

        let secondCommand = try extractCommand(from: readSettingsJSON()) ?? ""
        // Should contain the same sentinel count — no double-wrapping.
        let sentinel = "###AI-USAGE-CHAIN-START###"
        let firstCount = firstCommand.components(separatedBy: sentinel).count - 1
        let secondCount = secondCommand.components(separatedBy: sentinel).count - 1
        XCTAssertEqual(firstCount, secondCount, "Reinstall must not double-wrap the chain")
    }

    // MARK: - AC8: unparseable settings aborts install

    func testInstall_throwsWhenSettingsNotJSON() throws {
        try "not json {{{".write(to: settingsURL, atomically: true, encoding: .utf8)
        try createHelperBinary()
        XCTAssertThrowsError(try installer.installSettingsOnly()) { error in
            XCTAssertEqual(error as? InstallerError, .unparseableSettings)
        }
    }

    // MARK: - AC11: uninstall restores original command

    func testUninstall_restoresOriginalStringCommand() throws {
        try writeSettingsJSON(["statusLine": "original-cmd"])
        try createHelperBinary()
        try installer.installSettingsOnly()

        // Verify chained
        let chainedCommand = try extractCommand(from: readSettingsJSON()) ?? ""
        XCTAssertTrue(chainedCommand.contains("original-cmd"))

        // Uninstall
        try installer.uninstallSettingsOnly()

        let settings = try readSettingsJSON()
        let command = extractCommand(from: settings)
        XCTAssertEqual(command, "original-cmd")
    }

    func testUninstall_restoresOriginalObjectCommand() throws {
        try writeSettingsJSON(["statusLine": ["command": "ccstatusline"]])
        try createHelperBinary()
        try installer.installSettingsOnly()

        try installer.uninstallSettingsOnly()

        let settings = try readSettingsJSON()
        let statusLine = settings["statusLine"] as? [String: Any]
        let command = statusLine?["command"] as? String
        XCTAssertEqual(command, "ccstatusline")
    }

    func testUninstall_removesStatusLine_whenOnlyHelperWasSet() throws {
        // No prior statusLine — just our helper.
        try createHelperBinary()
        try installer.installSettingsOnly()

        let beforeSettings = try readSettingsJSON()
        XCTAssertNotNil(beforeSettings["statusLine"])

        try installer.uninstallSettingsOnly()

        let afterSettings = try readSettingsJSON()
        XCTAssertNil(afterSettings["statusLine"])
    }

    func testUninstall_noOp_whenNoStatusLine() throws {
        try writeSettingsJSON(["otherKey": "value"])
        // No statusLine key at all — uninstall should be a no-op.
        try installer.uninstallSettingsOnly()

        let settings = try readSettingsJSON()
        XCTAssertEqual(settings["otherKey"] as? String, "value")
        XCTAssertNil(settings["statusLine"])
    }

    func testUninstall_noOp_whenDifferentCommand() throws {
        try writeSettingsJSON(["statusLine": "some-other-command"])
        try installer.uninstallSettingsOnly()

        let settings = try readSettingsJSON()
        // Different command, not ours — unchanged.
        let command = extractCommand(from: settings)
        XCTAssertEqual(command, "some-other-command")
    }

    // MARK: - AC11: uninstall deletes cache file

    func testUninstall_deletesCache() throws {
        // Write a dummy cache and a helper binary.
        try "{}".write(to: cacheURL, atomically: true, encoding: .utf8)
        try createHelperBinary()

        // Full uninstall (not just settings-only).
        try installer.uninstall()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: cacheURL.path),
            "Cache file should be deleted on uninstall"
        )
    }

    // MARK: - AC11: uninstall deletes helper binary

    func testUninstall_deletesHelperBinary() throws {
        try createHelperBinary()
        try installer.uninstall()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: helperURL.path),
            "Helper binary should be deleted on uninstall"
        )
    }

    // MARK: - Chain escaping: special characters survive round-trip

    func testChain_roundTripsCommandWithSpecialChars() throws {
        let original = "echo \"hello $USER\" | grep 'foo'"
        try writeSettingsJSON(["statusLine": original])
        try createHelperBinary()
        try installer.installSettingsOnly()

        try installer.uninstallSettingsOnly()

        let settings = try readSettingsJSON()
        let command = extractCommand(from: settings)
        XCTAssertEqual(command, original)
    }

    // MARK: - Helpers

    /// Creates a dummy executable shell script at the helper destination so
    /// `isHelperInstalled()` returns `true`.
    private func createHelperBinary() throws {
        let dir = helperURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\necho ai-usage-helper".write(
            to: helperURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )
    }

    private func writeSettingsJSON(_ dict: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    private func readSettingsJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid JSON in settings"]
            )
        }
        return json
    }

    /// Extracts the `command` string from a `statusLine` value, which may
    /// be a string or a `{"command": "..."}` object.
    private func extractCommand(from settings: [String: Any]) -> String? {
        let statusLine = settings["statusLine"]
        if let str = statusLine as? String {
            return str
        }
        guard let dict = statusLine as? [String: Any] else { return nil }
        return dict["command"] as? String
    }
}
