@testable import ClaudeCodeProvider
import Core
import XCTest

/// Tests for the working-directory isolation added in (providers 06 AC1).
///
/// These verify the spawn's CWD behavior specifically — that the child runs in
/// the injected directory rather than the test runner's CWD, and that a
/// directory-creation failure aborts the spawn without clobbering the cache.
/// Kept in a separate file from `ClaudeCodeRefresherTests` to keep each test
/// type under the `type_body_length` threshold.
final class ClaudeCodeRefresherWorkingDirectoryTests: XCTestCase {
    private var tmpDir: URL!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-refresher-wd-tests-\(UUID().uuidString)")
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

    // MARK: - AC1 (providers 06): child runs in the injected working directory

    func testRefresh_spawnsInInjectedWorkingDirectory() async throws {
        // Dedicated temp dir for the child's CWD — distinct from the test
        // runner's CWD so we can prove the spawn did not inherit the parent.
        let injectedCWD = tmpDir.appendingPathComponent("injected-cwd")
        try FileManager.default.createDirectory(
            at: injectedCWD,
            withIntermediateDirectories: true
        )
        let pwdLogURL = tmpDir.appendingPathComponent("spawn-pwd.log")

        // The fake binary records `$PWD` — what the child actually sees as its
        // working directory — not the test runner's CWD.
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

        try await refresher.refresh()

        let recordedPWD = try String(contentsOf: pwdLogURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Compare via resolvingSymlinksInPath: `/var` is a symlink to
        // `/private/var` on macOS, so `$PWD` and the injected URL stringify
        // differently even when they denote the same directory.
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

    // MARK: - AC1 (providers 06): directory-creation failure leaves cache untouched

    func testRefresh_leavesCacheUntouchedWhenWorkingDirectoryCreationFails() async throws {
        // Seed a good cache (as the statusline helper would).
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

        try await refresher.refresh()

        let count = readInvocationCount(at: invocationCountURL)
        XCTAssertEqual(count, 0, "no child should start when the working directory cannot be created")

        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.writtenAt, 1000, "cache must be left exactly as it was")
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 42)
    }

    // MARK: - Helpers

    /// Writes `body` to `<tmpDir>/<name>`, `chmod +x`s it, and returns the
    /// file URL so it can be handed to `ClaudeCodeLocator(injectedPath:)`.
    private func writeFakeBinary(name: String, body: String) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    /// Reads the integer written by the counting fake binary. Returns 0 when
    /// the file does not exist (i.e. the spawn never ran).
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
