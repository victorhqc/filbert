@testable import ClaudeCodeProvider
import Core
import XCTest

final class StatuslineShellReplayTests: XCTestCase {
    func testOriginalErrexitSemanticsAndHelperReplayAcrossInvokingShells() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-shell-replay ' $-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = directory.appendingPathComponent("settings.json")
        let helper = directory.appendingPathComponent("helper")
        let replay = directory.appendingPathComponent("replay")
        let permissions = directory.appendingPathComponent("permissions")
        let helperScript = "#!/bin/sh\ncat > " + quote(replay.path) + "\n"
        try helperScript.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let original = "stat -f '%Lp' \"$FILBERT_INPUT\" > \(quote(permissions.path)); "
            + "set -e; false; printf SHOULD_NOT_PRINT"
        try JSONSerialization.data(withJSONObject: ["statusLine": original]).write(to: settings)
        let installer = StatuslineHelperInstaller(
            settingsURL: settings, helperDestURL: helper,
            cacheURL: directory.appendingPathComponent("cache"),
            errorLog: ErrorLog(directoryURL: directory.appendingPathComponent("logs"))
        )
        try installer.installSettingsOnly()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        )
        let statusLine = try XCTUnwrap(object["statusLine"] as? [String: Any])
        let command = try XCTUnwrap(statusLine["command"] as? String)
        let input = Data([0x7B, 0x00, 0x7D, 0x0A, 0x0A])
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh"] {
            let process = Process()
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", command]
            process.environment = ["PATH": "/usr/bin:/bin", "TMPDIR": directory.path]
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            try stdin.fileHandleForWriting.write(contentsOf: input)
            try stdin.fileHandleForWriting.close()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(stdout.fileHandleForReading.readDataToEndOfFile(), Data())
            XCTAssertEqual(stderr.fileHandleForReading.readDataToEndOfFile(), Data())
            XCTAssertEqual(try Data(contentsOf: replay), input)
            XCTAssertEqual(try String(contentsOf: permissions, encoding: .utf8), "600\n")
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.hasPrefix("filbert-statusline.") }))
        }
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
