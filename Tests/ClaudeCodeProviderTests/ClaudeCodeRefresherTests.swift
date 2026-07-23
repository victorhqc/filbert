@testable import ClaudeCodeProvider
import Core
import XCTest

/// Tests for the spawn mechanics in `ClaudeCodeRefresher` (providers 03).
///
/// The refresher treats `claude` as an opaque binary: it spawns whatever
/// path the locator returns and waits for exit. These tests exploit that by
/// pointing the locator at tiny shell scripts that record what the refresher
/// did — without ever needing a real `claude` install in CI.
final class ClaudeCodeRefresherTests: XCTestCase {
    private var tmpDir: URL!
    private var invocationLogURL: URL!
    private var invocationCountURL: URL!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-refresher-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true
        )
        invocationLogURL = tmpDir.appendingPathComponent("invocations.log")
        invocationCountURL = tmpDir.appendingPathComponent("invocations.count")
        cacheURL = tmpDir.appendingPathComponent("claude-code.json")
    }

    override func tearDown() {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        tmpDir = nil
        invocationLogURL = nil
        invocationCountURL = nil
        cacheURL = nil
        super.tearDown()
    }

    /// A refresher wired to the temp cache file so tests never touch the real
    /// `~/.cache/filbert/claude-code.json`.
    private func makeRefresher(
        binaryPath: String?,
        spawnTimeout: TimeInterval = 30,
        terminateGrace: TimeInterval = 2,
        spawnDebounce: TimeInterval = 60
    ) -> ClaudeCodeRefresher {
        ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: binaryPath),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            spawnTimeout: spawnTimeout,
            terminateGrace: terminateGrace,
            spawnDebounce: spawnDebounce
        )
    }

    // MARK: - AC1: argv is exactly the documented flags

    func testRefresh_spawnsClaudeWithDocumentedArgv() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-argv",
            body: """
            #!/bin/bash
            echo "$@" >> "\(invocationLogURL.path)"
            exit 0
            """
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        try await refresher.refresh()

        let logged = try String(contentsOf: invocationLogURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            logged,
            ClaudeCodeRefresher.spawnArguments.joined(separator: " ")
        )
    }

    // MARK: - AC1 (providers 03): stream-json output is parsed into the cache

    func testRefresh_parsesUsageOutputIntoCache() async throws {
        // The fake binary emits what `claude -p "/usage" --output-format json`
        // emits: a JSON object whose `result` holds the usage text.
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-usage",
            body: usageFakeBinaryBody(session: 77, week: 37)
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        try await refresher.refresh()

        let cache = try XCTUnwrap(
            StatuslineCacheStore(cacheURL: cacheURL).read(),
            "Refresher should have written a cache from the /usage output"
        )
        let fiveHour = try XCTUnwrap(cache.rateLimits?.fiveHour)
        XCTAssertEqual(fiveHour.usedPercentage, 77)
        XCTAssertNotNil(fiveHour.resetsAt, "reset phrase should parse to a timestamp")

        let sevenDay = try XCTUnwrap(cache.rateLimits?.sevenDay)
        XCTAssertEqual(sevenDay.usedPercentage, 37)
        XCTAssertNotNil(sevenDay.resetsAt)
    }

    // MARK: - Reset-phrase parsing

    func testParseResetPhrase_decodesMonthDayTimeInZone() throws {
        let epoch = try XCTUnwrap(
            ClaudeCodeRefresher.parseResetPhrase("Jul 21 at 12:59am (Europe/Berlin)")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let comps = calendar.dateComponents(
            [.month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: epoch)
        )
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 21)
        XCTAssertEqual(comps.hour, 0) // 12:59am → 00:59
        XCTAssertEqual(comps.minute, 59)
    }

    func testParseResetPhrase_handlesHourWithoutMinutesAndPM() throws {
        let epoch = try XCTUnwrap(
            ClaudeCodeRefresher.parseResetPhrase("Dec 3 at 11pm (America/New_York)")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let comps = calendar.dateComponents([.month, .day, .hour], from: Date(timeIntervalSince1970: epoch))
        XCTAssertEqual(comps.month, 12)
        XCTAssertEqual(comps.day, 3)
        XCTAssertEqual(comps.hour, 23) // 11pm → 23:00
    }

    // MARK: - AC6 (providers 03): a spawn with no usable output never clobbers

    func testRefresh_leavesCacheUntouchedWhenNoUsage() async throws {
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

        // A spawn that prints nothing on stdout (e.g. logged out / CLI drift).
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-empty",
            body: "#!/bin/bash\nexit 1\n"
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        try await refresher.refresh()

        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.writtenAt, 1000, "cache must be left exactly as it was")
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 42)
    }

    // MARK: - AC2: a hung process is terminated within the timeout + grace

    func testRefresh_terminatesHungProcess() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-hang",
            body: """
            #!/bin/bash
            sleep 60
            """
        )

        // Tighten the timeout so the test doesn't take 30s. The spawn
        // itself is a fake `sleep 60`, simulating a process that never
        // exits. The refresher must terminate it within the configured
        // window plus the SIGKILL grace period.
        let refresher = makeRefresher(
            binaryPath: fakeBinary.path,
            spawnTimeout: 1,
            terminateGrace: 1
        )

        let start = Date()
        try await refresher.refresh()
        let elapsed = Date().timeIntervalSince(start)

        // Timeout + grace + a little slack for the 100ms polling.
        let upperBound = 1.0 + 1.0 + 2.0
        XCTAssertLessThan(
            elapsed,
            upperBound,
            "Hung process should be terminated within \(upperBound)s, took \(elapsed)s"
        )
    }

    // MARK: - AC4: debounce skips a second spawn within the window

    func testRefresh_debouncesSecondCallWithinWindow() async throws {
        let fakeBinary = try writeCountingBinary()
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        try await refresher.refresh()
        try await refresher.refresh()

        let count = try readInvocationCount()
        XCTAssertEqual(count, 1, "Second call within debounce window should be skipped")
    }

    // MARK: - Helpers

    /// Writes an executable shell script that records each invocation by
    /// appending `counted` to `invocationCountURL`.
    private func writeCountingBinary() throws -> URL {
        try writeFakeBinary(
            name: "fake-claude-count",
            body: """
            #!/bin/bash
            echo counted >> "\(invocationCountURL.path)"
            """
        )
    }

    // MARK: - AC4: in-flight callers share one OS process

    func testRefresh_concurrentCallersShareOneProcess() async throws {
        // The fake binary sleeps briefly so the two concurrent callers
        // actually overlap — without the sleep, the first spawn could
        // finish before the second call enters the actor, and the test
        // would pass for the wrong reason (both calls saw no in-flight task
        // because the first had already completed).
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-overlap",
            body: """
            #!/bin/bash
            sleep 0.5
            echo counted >> "\(invocationCountURL.path)"
            """
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        // Fire both refreshes concurrently; both should await the same
        // in-flight task and only one `claude` process should run.
        async let first: Void = refresher.refresh()
        async let second: Void = refresher.refresh()
        _ = try await (first, second)

        let count = try readInvocationCount()
        XCTAssertEqual(count, 1, "Concurrent callers must coalesce onto one spawn")
    }

    // MARK: - AC1 / Risks: binary not found surfaces as a thrown error

    func testRefresh_throwsBinaryNotFoundWhenLocatorReturnsNil() async throws {
        let refresher = makeRefresher(binaryPath: nil)

        do {
            try await refresher.refresh()
            XCTFail("Expected binaryNotFound")
        } catch let error as ClaudeCodeRefresherError {
            XCTAssertEqual(error, .binaryNotFound)
        }
    }

    // MARK: - AC4: a failed spawn still suppresses follow-up clicks

    func testRefresh_failedSpawnStillDebounces() async throws {
        // The locator returns nil, so refresh() throws binaryNotFound.
        // The next call within the debounce window should also short-circuit
        // (it would be a no-op regardless, but the contract is that the
        // debounce timestamp is set on attempt).
        let refresher = makeRefresher(binaryPath: nil)

        _ = try? await refresher.refresh()
        // Second call should return without throwing because it's debounced
        // (returns early before re-attempting the binary lookup).
        try await refresher.refresh()
    }

    /// Shell body for a fake `claude` that echoes a `/usage --output-format
    /// json` payload: a single JSON object whose `result` holds the usage text
    /// (newlines encoded as `\n`, matching what `claude` actually emits).
    private func usageFakeBinaryBody(session: Int, week: Int) -> String {
        let line1 = "Current session: \(session)% used · resets Jul 21 at 12:59am (Europe/Berlin)"
        let line2 = "Current week (all models): \(week)% used · resets Jul 24 at 5:59am (Europe/Berlin)"
        let line3 = "Current week (Fable): 0% used"
        let result = "\(line1)\\n\(line2)\\n\(line3)"
        return """
        #!/bin/bash
        cat <<'JSON'
        {"type":"result","is_error":false,"result":"\(result)"}
        JSON
        """
    }

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
    private func readInvocationCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: invocationCountURL.path) else {
            return 0
        }
        let text = try String(contentsOf: invocationCountURL, encoding: .utf8)
        return text.components(separatedBy: .newlines)
            .filter { $0 == "counted" }
            .count
    }
}
