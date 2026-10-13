@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeRefresherWorkingDirectoryTests: XCTestCase {
    private var tmpDir: URL!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-refresher-wd-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true
        )
        cacheURL = tmpDir.appendingPathComponent("claude-code.json")
    }

    override func tearDown() {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        tmpDir = nil
        cacheURL = nil
        super.tearDown()
    }

    // MARK: - child runs in the injected working directory

    func testRefresh_spawnsInInjectedWorkingDirectory() async throws {
        // Distinct from the runner's working directory, to prove the child did not inherit it.
        let injectedCWD = tmpDir.appendingPathComponent("injected-cwd")
        try FileManager.default.createDirectory(
            at: injectedCWD,
            withIntermediateDirectories: true
        )
        let pwdLogURL = tmpDir.appendingPathComponent("spawn-pwd.log")

        // Records `$PWD`, the working directory the child sees.
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-pwd",
            body: """
            #!/bin/bash
            echo "$PWD" > "\(pwdLogURL.path)"
            exit 0
            """
        )
        let refresher = ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: fakeBinary.path),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            spawnTimeout: 30,
            terminateGrace: 2,
            spawnDebounce: 60,
            workingDirectoryProvider: { injectedCWD }
        )

        do {
            try await refresher.refresh()
            XCTFail("Expected missing usage failure")
        } catch let error as ClaudeCodeRefresherError {
            guard case .noUsageData = error else {
                return XCTFail("Expected noUsageData, got \(error)")
            }
        }

        let recordedPWD = try String(contentsOf: pwdLogURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `/var` links to `/private/var`, so compare resolved paths.
        XCTAssertEqual(
            URL(fileURLWithPath: recordedPWD).resolvingSymlinksInPath(),
            injectedCWD.resolvingSymlinksInPath(),
            "child must run in the injected working directory, not the test runner's CWD"
        )
        XCTAssertNotEqual(
            recordedPWD,
            FileManager.default.currentDirectoryPath,
            "child must not inherit the test runner's current directory"
        )
    }

    // MARK: - directory-creation failure leaves cache untouched

    func testRefresh_leavesCacheUntouchedWhenWorkingDirectoryCreationFails() async throws {
        try StatuslineCacheStore(cacheURL: cacheURL).write(
            StatuslineCache(
                writtenAt: 1000,
                rateLimits: RateLimits(
                    fiveHour: Window(usedPercentage: 42, resetsAt: 2000),
                    sevenDay: nil
                )
            )
        )

        // A fake binary that would record a spawn if it ever ran.
        let invocationCountURL = tmpDir.appendingPathComponent("invocations.count")
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-count",
            body: """
            #!/bin/bash
            echo counted >> "\(invocationCountURL.path)"
            """
        )

        // Provider returns nil: directory creation "failed".
        let refresher = ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: fakeBinary.path),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            spawnTimeout: 30,
            terminateGrace: 2,
            spawnDebounce: 60,
            workingDirectoryProvider: { nil }
        )

        do {
            try await refresher.refresh()
            XCTFail("Expected working directory failure")
        } catch let error as ClaudeCodeRefresherError {
            XCTAssertEqual(error, .workingDirectoryUnavailable)
        }

        let count = readInvocationCount(at: invocationCountURL)
        XCTAssertEqual(count, 0, "no child should start when the working directory cannot be created")

        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.writtenAt, 1000, "cache must be left exactly as it was")
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 42)
    }

    // MARK: - Helpers

    private func writeFakeBinary(name: String, body: String) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    private func readInvocationCount(at url: URL) -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.components(separatedBy: .newlines)
            .filter { $0 == "counted" }
            .count
    }
}
