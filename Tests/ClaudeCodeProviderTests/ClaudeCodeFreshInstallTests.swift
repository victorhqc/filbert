@testable import ClaudeCodeProvider
import Core
import XCTest

private struct CommandResult {
    let status: Int32
    let output: Data
    let error: Data
}

final class ClaudeCodeFreshInstallTests: XCTestCase {
    private var directory: URL!
    private var settingsURL: URL!
    private var helperURL: URL!
    private var cacheURL: URL!
    private var log: ErrorLog!
    private var installer: StatuslineHelperInstaller!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert ' $;` fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        helperURL = directory.appendingPathComponent("helper ' $;` binary")
        cacheURL = directory.appendingPathComponent("cache ' $;`.json")
        log = ErrorLog(directoryURL: directory.appendingPathComponent("logs ' $;`"))
        installer = StatuslineHelperInstaller(
            settingsURL: settingsURL, helperDestURL: helperURL, cacheURL: cacheURL, errorLog: log
        )
        XCTAssertFalse(installer.canRemoveHelper())
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testInvokingShellForwardsIdenticalInputAndPreservesOriginalOutput() throws {
        let originalInput = directory.appendingPathComponent("original-input")
        let helperInput = directory.appendingPathComponent("helper-input")
        let fakeHelper = directory.appendingPathComponent("fake-helper")
        try executable("#!/bin/sh\ncat > \(quote(helperInput.path))\nprintf 'hidden'\n", at: fakeHelper)
        let original = "cat > \(quote(originalInput.path)); "
            + "value=$(printf 'expanded'); printf '%s:%s:%s' \"$value\" \"$(cat \(quote(originalInput.path)))\" \"$0\""
        try writeSettings(["statusLine": ["command": original, "padding": 3]])
        try installer.install(helperExecutableURL: fakeHelper)
        XCTAssertTrue(installer.canRemoveHelper())
        let command = try installedCommand()
        let input = Data("{\"text\":\"$HOME `echo nope` \\\\ \\\" ' %\"}\n\n".utf8)
        let inputText = try XCTUnwrap(String(data: input, encoding: .utf8)).trimmingCharacters(in: .newlines)
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh"] {
            let syntax = try run(shell, arguments: ["-n", "-c", command])
            XCTAssertEqual(syntax.status, 0)
            let result = try run(shell, arguments: ["-c", command, "invoking-shell"], input: input)
            XCTAssertEqual(result.status, 0)
            XCTAssertEqual(result.error, Data())
            XCTAssertEqual(try Data(contentsOf: originalInput), input)
            XCTAssertEqual(try Data(contentsOf: helperInput), input)
            XCTAssertEqual(String(data: result.output, encoding: .utf8), "expanded:\(inputText):invoking-shell")
        }
        try installer.install(helperExecutableURL: fakeHelper)
        XCTAssertEqual(try installedCommand(), command)
        try installer.uninstall()
        let restored = try settings()
        let statusLine = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, original)
        XCTAssertEqual(statusLine["padding"] as? Int, 3)
        XCTAssertNil(statusLine["type"])
    }

    func testPackagedHelperCreatesFirstCacheAndProviderQuotaThenRetainsMalformedInput() async throws {
        let resources = directory.appendingPathComponent("Filbert.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let builtHelper = try XCTUnwrap(StatuslineHelperResource.resolve())
        let packagedHelper = resources.appendingPathComponent(StatuslineHelperResource.executableName)
        try FileManager.default.copyItem(at: builtHelper, to: packagedHelper)
        let resolved = try XCTUnwrap(StatuslineHelperResource.resolve(
            resourceURL: resources,
            executableURL: directory.appendingPathComponent("Filbert.app/Contents/MacOS/Filbert"),
            moduleURL: directory.appendingPathComponent("unavailable.bundle")
        ))
        XCTAssertEqual(resolved, packagedHelper)
        try writeSettings(["statusLine": ["command": "printf 'previous-output'", "padding": 2]])
        try installer.install(helperExecutableURL: resolved)
        XCTAssertTrue(installer.isHelperInstalled())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        let command = try installedCommand()
        let payload = Data("""
        {"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1900000000},
        "seven_day":{"used_percentage":63,"resets_at":1900200000}}}
        """.utf8)
        let result = try run("/bin/sh", arguments: ["-c", command], input: payload)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, Data("previous-output".utf8))
        XCTAssertEqual(result.error, Data())
        let store = StatuslineCacheStore(cacheURL: cacheURL, errorLog: log)
        let firstCache = try XCTUnwrap(store.read())
        let savedBytes = try Data(contentsOf: cacheURL)
        let provider = ClaudeCodeProvider(
            locator: ClaudeCodeLocator(injectedPath: "/fake/claude"),
            cacheStore: store, installer: installer, errorLog: log
        )
        let quota = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: ClaudeCodeProvider.baseURL)
        XCTAssertEqual(quota.lines.map(\.percentage), [42, 63])
        XCTAssertEqual(quota.lines.map { $0.resetDate?.timeIntervalSince1970 }, [1_900_000_000, 1_900_200_000])
        XCTAssertEqual(quota.lastUpdated.timeIntervalSince1970, firstCache.writtenAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))

        try assertInvalidInputRetainsCache(command: command, savedBytes: savedBytes)
        try installer.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertFalse(installer.isHelperInstalled())
        try installer.install(helperExecutableURL: resolved)
        XCTAssertTrue(installer.isHelperInstalled())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testActualHelperDoesNotFabricateAbsentFieldsOrEmptyWindows() throws {
        let helper = try XCTUnwrap(StatuslineHelperResource.resolve())
        try installer.install(helperExecutableURL: helper)
        for input in [
            #"{"rate_limits":{"five_hour":{"used_percentage":12}}}"#,
            #"{"rate_limits":{"five_hour":{"resets_at":1900000000}}}"#,
            #"{"rate_limits":{"five_hour":{},"seven_day":{}}}"#,
            #"{}"#,
        ] {
            _ = try run("/bin/sh", arguments: ["-c", installedCommand()], input: Data(input.utf8))
            let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL, errorLog: log).read())
            if input.contains("used_percentage") {
                XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 12)
                XCTAssertNil(cache.rateLimits?.fiveHour?.resetsAt)
            } else if input.contains("resets_at") {
                XCTAssertNil(cache.rateLimits?.fiveHour?.usedPercentage)
                XCTAssertEqual(cache.rateLimits?.fiveHour?.resetsAt, 1_900_000_000)
            } else {
                XCTAssertNil(cache.rateLimits)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
    }

    func testBrokenPartialConfigurationCanRetryAndRollbackPreservesOriginalFiles() throws {
        let source = directory.appendingPathComponent("prebuilt")
        try executable("#!/bin/sh\nexit 0\n", at: source)
        try executable("#!/bin/sh\nprintf old\n", at: helperURL)
        XCTAssertFalse(installer.isHelperInstalled())
        let metadata: [String: Any] = [
            "type": "custom-type", "command": "printf original", "padding": 4,
            "refreshInterval": 7, "nested": ["secret": "SETTINGS_PRIVATE"],
        ]
        try writeSettings(["statusLine": metadata, "other": ["value": true]])
        try installer.install(helperExecutableURL: source)
        XCTAssertTrue(installer.isHelperInstalled())
        try installer.uninstallSettingsOnly()
        let restored = try settings()["statusLine"] as? NSDictionary
        XCTAssertEqual(restored, metadata as NSDictionary)

        try "invalid SETTINGS_PRIVATE".write(to: settingsURL, atomically: true, encoding: .utf8)
        let helperBefore = try Data(contentsOf: helperURL)
        let settingsBefore = try Data(contentsOf: settingsURL)
        XCTAssertThrowsError(try installer.install(helperExecutableURL: source))
        XCTAssertEqual(try Data(contentsOf: helperURL), helperBefore)
        XCTAssertEqual(try Data(contentsOf: settingsURL), settingsBefore)
        XCTAssertFalse(installer.isHelperInstalled())
        try writeSettings([:])
        try installer.install(helperExecutableURL: source)
        XCTAssertTrue(installer.isHelperInstalled())
        try writeSettings(["statusLine": ["type": "command", "command": "echo \(helperURL.path)"]])
        XCTAssertFalse(installer.isHelperInstalled())
    }

    func testMalformedSettingsRemovalThrowsWithoutDeletingHelper() throws {
        try executable("#!/bin/sh\nexit 0\n", at: helperURL)
        try Data("bad settings".utf8).write(to: settingsURL)
        XCTAssertThrowsError(try installer.uninstall())
        XCTAssertTrue(FileManager.default.fileExists(atPath: helperURL.path))
    }

    func testActualHelperLogsCacheWriteFailureWithoutRawInputOrPaths() throws {
        let helper = try XCTUnwrap(StatuslineHelperResource.resolve())
        try installer.install(helperExecutableURL: helper)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let result = try run(
            "/bin/sh", arguments: ["-c", installedCommand()],
            input: Data(#"{"private":"SENTINEL_PRIVATE","rate_limits":{"five_hour":{"used_percentage":2}}}"#.utf8)
        )
        XCTAssertEqual(result.error, Data())
        XCTAssertEqual(result.output, Data())
        let records = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertTrue(records.contains("cache-write-failed"))
        XCTAssertFalse(records.contains("SENTINEL_PRIVATE"))
        XCTAssertFalse(records.contains(cacheURL.path))
        XCTAssertEqual(records.split(separator: "\n").count, 1)
    }

    private func assertInvalidInputRetainsCache(command: String, savedBytes: Data) throws {
        let invalid = Data(#"{"rate_limits":{"five_hour":{"used_percentage":"SENTINEL_PRIVATE"}}}"#.utf8)
        let failedInput = try run("/bin/sh", arguments: ["-c", command], input: invalid)
        XCTAssertEqual(failedInput.error, Data())
        XCTAssertEqual(try Data(contentsOf: cacheURL), savedBytes)
        let firstRecord = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertTrue(firstRecord.contains("invalid-input"))
        XCTAssertFalse(firstRecord.contains("SENTINEL_PRIVATE"))
        XCTAssertEqual(firstRecord.split(separator: "\n").count, 1)
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh"] {
            let nulInput = try run(shell, arguments: ["-c", command], input: Data([0x7B, 0x00, 0x7D]))
            XCTAssertEqual(nulInput.error, Data())
            XCTAssertEqual(try Data(contentsOf: cacheURL), savedBytes)
        }
        let records = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertEqual(records.split(separator: "\n").count, 4)
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func executable(_ text: String, at url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writeSettings(_ object: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: settingsURL)
    }

    private func settings() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
    }

    private func installedCommand() throws -> String {
        let statusLine = try XCTUnwrap(settings()["statusLine"] as? [String: Any])
        return try XCTUnwrap(statusLine["command"] as? String)
    }

    private func run(
        _ executable: String, arguments: [String], input: Data = Data()
    ) throws -> CommandResult {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = directory
        process.environment = [
            "HOME": directory.path, "PATH": "/usr/bin:/bin",
            "SHELL": "/does/not/exist", "TMPDIR": directory.path,
        ]
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: input)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            output: stdout.fileHandleForReading.readDataToEndOfFile(),
            error: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}
