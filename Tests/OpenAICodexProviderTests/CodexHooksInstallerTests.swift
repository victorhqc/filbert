import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

final class CodexHooksInstallerTests: XCTestCase {
    private var directory: URL!
    private var installer: CodexHooksInstaller!

    private var hooksURL: URL {
        installer.hooksURL
    }

    private var signalURL: URL {
        installer.signalURL
    }

    override func setUpWithError() throws {
        DisplayLanguage.selectedLanguageCode = "en"
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        installer = CodexHooksInstaller(
            hooksURL: directory.appendingPathComponent(".codex/hooks.json"),
            signalURL: directory.appendingPathComponent("cache dir/filbert/codex-activity")
        )
    }

    override func tearDownWithError() throws {
        DisplayLanguage.selectedLanguageCode = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testInstallCreatesAMissingFileWithFourAsyncHandlers() throws {
        try installer.install()

        let hooks = try XCTUnwrap(readJSON()["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["UserPromptSubmit", "Stop", "PostModelRequest", "PostToolUse"])
        for event in hooks.keys {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1)
            XCTAssertNil(groups.first?["matcher"], "\(event) must run for every occurrence")
            let handlers = try XCTUnwrap(groups.first?["hooks"] as? [[String: Any]])
            XCTAssertEqual(handlers.count, 1)
            let handler = try XCTUnwrap(handlers.first)
            XCTAssertEqual(handler["type"] as? String, "command")
            XCTAssertEqual(handler["command"] as? String, installer.command)
            XCTAssertEqual(handler["async"] as? Bool, true)
            XCTAssertEqual(handler["timeout"] as? Int, 5)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: signalURL.deletingLastPathComponent().path))
    }

    func testInstallTreatsAnEmptyFileAsNoHooks() throws {
        try writeRaw("  \n")

        try installer.install()

        XCTAssertEqual(try handlerCount(for: "Stop"), 1)
        XCTAssertEqual(try handlerCount(for: "UserPromptSubmit"), 1)
    }

    func testInstallKeepsEveryOtherKeyEventGroupAndHandler() throws {
        let original = try userHooksFile()
        try writeJSON(original)

        try installer.install()

        let root = try readJSON()
        XCTAssertEqual(root["description"] as? String, "My hooks")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let originalHooks = try XCTUnwrap(original["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["PreToolUse"] as? NSArray, originalHooks["PreToolUse"] as? NSArray)
        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let originalStop = try XCTUnwrap(originalHooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 2)
        XCTAssertEqual(stopGroups.first as NSDictionary?, originalStop.first as NSDictionary?)
    }

    func testASecondInstallAddsNoDuplicates() throws {
        try installer.install()
        let firstWrite = try Data(contentsOf: hooksURL)

        try installer.install()

        XCTAssertEqual(try Data(contentsOf: hooksURL), firstWrite)
        XCTAssertEqual(try handlerCount(for: "Stop"), 1)
        XCTAssertEqual(try handlerCount(for: "UserPromptSubmit"), 1)
    }

    func testInstallUpgradesATwoHookInstallWithoutMovingItsTrustedHandlers() throws {
        let userStop: [String: Any] = ["hooks": [["type": "command", "command": "say done"]]]
        let filbertGroup: [String: Any] = [
            "hooks": [["type": "command", "command": installer.command, "async": true, "timeout": 5]],
        ]
        try writeJSON(["hooks": ["UserPromptSubmit": [filbertGroup], "Stop": [userStop, filbertGroup]]])

        try installer.install()

        let hooks = try XCTUnwrap(readJSON()["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["UserPromptSubmit"] as? NSArray, [filbertGroup] as NSArray)
        XCTAssertEqual(hooks["Stop"] as? NSArray, [userStop, filbertGroup] as NSArray)
        XCTAssertEqual(try handlerCount(for: "PostModelRequest"), 1)
        XCTAssertEqual(try handlerCount(for: "PostToolUse"), 1)
    }

    func testInstallNeverTouchesConfigToml() throws {
        let configURL = hooksURL.deletingLastPathComponent().appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let config = """
        [features]
        hooks = true

        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "echo inline"
        """
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        try installer.install()
        try installer.remove()

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), config)
    }

    func testInvalidJSONIsLeftUnchangedAndNamesThePath() throws {
        let raw = "{ \"hooks\": "
        try writeRaw(raw)

        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? CodexHooksError, .unreadableHooksFile(path: hooksURL.path))
            XCTAssertTrue(error.localizedDescription.contains(hooksURL.path))
        }
        XCTAssertThrowsError(try installer.remove())
        XCTAssertEqual(try String(contentsOf: hooksURL, encoding: .utf8), raw)
    }

    func testAnUnrecognizedShapeIsLeftUnchanged() throws {
        for raw in [
            #"["not", "an", "object"]"#,
            #"{"hooks": ["Stop"]}"#,
            #"{"hooks": {"Stop": {"hooks": []}}}"#,
            #"{"hooks": {"Stop": [{"hooks": "touch"}]}}"#,
        ] {
            try writeRaw(raw)

            XCTAssertThrowsError(try installer.install(), raw) { error in
                XCTAssertEqual(error as? CodexHooksError, .unrecognizedHooksFile(path: hooksURL.path))
            }
            XCTAssertThrowsError(try installer.remove(), raw)
            XCTAssertEqual(try String(contentsOf: hooksURL, encoding: .utf8), raw)
        }
    }

    func testRemoveRestoresAFileWithOtherHooks() throws {
        let original = try userHooksFile()
        try writeJSON(original)
        try installer.install()

        try installer.remove()

        XCTAssertEqual(try readJSON() as NSDictionary, original as NSDictionary)
    }

    func testRemoveDeletesAFileThatOnlyHeldFilbertsHooks() throws {
        try installer.install()

        try installer.remove()

        XCTAssertFalse(FileManager.default.fileExists(atPath: hooksURL.path))
    }

    func testRemoveKeepsAUserHandlerThatSharesFilbertsGroup() throws {
        try writeJSON([
            "hooks": [
                "Stop": [[
                    "hooks": [
                        ["type": "command", "command": "echo mine"],
                        ["type": "command", "command": installer.command, "async": true, "timeout": 5],
                    ],
                ]],
            ],
        ])

        try installer.remove()

        let groups = try XCTUnwrap((readJSON()["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        let handlers = try XCTUnwrap(groups.first?["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers.map { $0["command"] as? String }, ["echo mine"])
    }

    func testRemoveTakesOutEveryFilbertHandlerFromAMixedFile() throws {
        let filbertGroup: [String: Any] = ["hooks": [["type": "command", "command": installer.command]]]
        let userGroup: [String: Any] = ["hooks": [["type": "command", "command": "echo mine"]]]
        try writeJSON([
            "hooks": [
                "Stop": [filbertGroup],
                "PostToolUse": [userGroup, filbertGroup],
                "PostModelRequest": [filbertGroup],
            ],
        ])

        try installer.remove()

        XCTAssertEqual(try readJSON() as NSDictionary, ["hooks": ["PostToolUse": [userGroup]]] as NSDictionary)
    }

    func testRemoveLeavesAnUnrelatedEmptyEventAlone() throws {
        try writeJSON(["hooks": ["SessionStart": [] as [Any]]])
        try installer.install()

        try installer.remove()

        XCTAssertEqual(try readJSON() as NSDictionary, ["hooks": ["SessionStart": [] as [Any]]] as NSDictionary)
    }

    func testRemoveDeletesTheSignalFileEvenWithoutAHooksFile() throws {
        try FileManager.default.createDirectory(
            at: signalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: signalURL.path, contents: nil)

        try installer.remove()

        XCTAssertFalse(FileManager.default.fileExists(atPath: signalURL.path))
    }

    func testStatusFollowsInstallAndTheFirstHookRun() throws {
        XCTAssertTrue(isNotInstalled(installer.status()))

        try writeJSON([
            "hooks": ["Stop": [["hooks": [["type": "command", "command": installer.command]]]]],
        ])
        XCTAssertTrue(isNotInstalled(installer.status()), "one missing handler is not installed")

        try installer.install()
        guard case let .awaitingFirstSignal(text) = installer.status() else {
            return XCTFail("Expected awaitingFirstSignal")
        }
        XCTAssertTrue(text?.resolved.contains("/hooks") == true)
        XCTAssertTrue(text?.resolved.contains("Settings > Hooks") == true)
        XCTAssertTrue(text?.resolved.contains("other tools") == true)
        XCTAssertFalse(text?.resolved.contains("Zed") == true)

        try runHookCommand()
        guard case .active = installer.status() else {
            return XCTFail("Expected active after the hook ran")
        }

        try installer.install()
        guard case .awaitingFirstSignal = installer.status() else {
            return XCTFail("A reinstall must wait for a new hook run")
        }
    }

    func testStatusIsNotInstalledUntilAllFourHandlersArePresent() throws {
        let filbertGroup: [String: Any] = ["hooks": [["type": "command", "command": installer.command]]]
        try writeJSON(["hooks": ["UserPromptSubmit": [filbertGroup], "Stop": [filbertGroup]]])
        XCTAssertTrue(isNotInstalled(installer.status()), "an install from an earlier version")

        try writeJSON([
            "hooks": ["UserPromptSubmit": [filbertGroup], "Stop": [filbertGroup], "PostModelRequest": [filbertGroup]],
        ])
        XCTAssertTrue(isNotInstalled(installer.status()), "three of four handlers")
    }

    func testStatusTextsDoNotCountTheHooks() throws {
        guard case let .notInstalled(description) = installer.status() else {
            return XCTFail("Expected notInstalled")
        }
        XCTAssertTrue(description?.resolved.contains("adds Filbert's hooks to ~/.codex/hooks.json") == true)

        try installer.install()
        guard case let .awaitingFirstSignal(nextSteps) = installer.status() else {
            return XCTFail("Expected awaitingFirstSignal")
        }
        XCTAssertTrue(nextSteps?.resolved.contains("trust all Filbert hooks") == true)
        XCTAssertFalse(nextSteps?.resolved.contains("both") == true)
    }

    func testStatusExplainsAnUnreadableFile() throws {
        try writeRaw("not json")

        guard case let .notInstalled(text) = installer.status() else {
            return XCTFail("Expected notInstalled")
        }
        XCTAssertTrue(text?.resolved.contains(hooksURL.path) == true)
    }

    func testTheHookCommandTouchesTheSignalFileThroughAShell() throws {
        XCTAssertEqual(installer.command, "/usr/bin/touch '\(signalURL.path)'")
        try installer.install()

        try runHookCommand()

        XCTAssertTrue(FileManager.default.fileExists(atPath: signalURL.path))
    }

    // MARK: - Helpers

    private func userHooksFile() throws -> [String: Any] {
        [
            "description": "My hooks",
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/usr/bin/python3 check.py", "statusMessage": "Checking"]],
                ]],
                "Stop": [[
                    "hooks": [["type": "command", "command": "say done", "timeout": 30]],
                ]],
            ],
        ]
    }

    private func runHookCommand() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", installer.command]
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func isNotInstalled(_ status: ActivitySignalStatus) -> Bool {
        if case .notInstalled = status {
            return true
        }
        return false
    }

    private func handlerCount(for event: String) throws -> Int {
        let groups = try (readJSON()["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.reduce(0) { $0 + (($1["hooks"] as? [Any])?.count ?? 0) }
    }

    private func readJSON() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as? [String: Any])
    }

    private func writeJSON(_ object: [String: Any]) throws {
        try writeData(JSONSerialization.data(withJSONObject: object))
    }

    private func writeRaw(_ raw: String) throws {
        try writeData(Data(raw.utf8))
    }

    private func writeData(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: hooksURL)
    }
}
