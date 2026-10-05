@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeRefresherSubprocessTests: XCTestCase {
    private var tmpDir: URL!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-refresher-subprocess-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
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

    func testRefresh_recordsProcessFailureMetadata() async throws {
        let sentinel = "SECRET_STDERR_PROMPT_ACCOUNT_12345"
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-stderr",
            body: "#!/bin/bash\nprintf '%s' '\(sentinel)' 1>&2\nexit 3\n"
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        let error = try await capturedError(from: refresher)
        guard case let .processFailed(diagnostic) = error else {
            return XCTFail("Expected processFailed, got \(error)")
        }
        XCTAssertEqual(diagnostic.exitStatus, 3)
        XCTAssertEqual(diagnostic.stdoutBytes, 0)
        XCTAssertEqual(diagnostic.stderrBytes, sentinel.utf8.count)
        XCTAssertFalse(diagnostic.stdoutTruncated)
        XCTAssertNil(diagnostic.cliReportedError)
        XCTAssertNil(diagnostic.outputFailure)
        XCTAssertFalse(error.localizedDescription.contains(sentinel))

        let log = ErrorLog(directoryURL: tmpDir.appendingPathComponent("logs"))
        XCTAssertTrue(log.record(
            component: "app", operation: "proactive-refresh", code: "operation-failed",
            providerID: "claude-code", error: error
        ))
        let record = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertFalse(record.contains(sentinel))
        XCTAssertTrue(record.contains("process-failed"))
    }

    func testRefresh_recordsCLIReportedErrorFromErrorResponse() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-error-json",
            body: """
            #!/bin/bash
            cat <<'JSON'
            {"is_error":true,"result":"Current session: 77% used · resets Jul 21 at 12:59am (Europe/Berlin)"}
            JSON
            exit 0
            """
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        let error = try await capturedError(from: refresher)
        guard case let .noUsageData(diagnostic) = error else {
            return XCTFail("Expected noUsageData, got \(error)")
        }
        XCTAssertEqual(diagnostic.exitStatus, 0)
        XCTAssertEqual(diagnostic.cliReportedError, true)
        XCTAssertEqual(diagnostic.outputFailure, .cliReportedError)
        XCTAssertEqual(error.diagnosticCode, "usage-data-missing")
    }

    func testRefresh_recordsBooleanIsErrorFalse() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-false",
            body: "#!/bin/bash\ncat <<'JSON'\n{\"is_error\":false,\"result\":\"banner\"}\nJSON\n"
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        let error = try await capturedError(from: refresher)
        guard case let .noUsageData(diagnostic) = error else {
            return XCTFail("Expected noUsageData, got \(error)")
        }
        XCTAssertEqual(diagnostic.cliReportedError, false)
        XCTAssertEqual(diagnostic.outputFailure, .usageWindowsMissing)
    }

    func testRefresh_rejectsOutputOverCaptureLimitWithoutHanging() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-large",
            body: "#!/bin/bash\nyes A | head -c 200000\nexit 0\n"
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path, outputCaptureLimit: 64 * 1024)

        let start = Date()
        let error = try await capturedError(from: refresher)
        let elapsed = Date().timeIntervalSince(start)

        guard case let .noUsageData(diagnostic) = error else {
            return XCTFail("Expected noUsageData, got \(error)")
        }
        XCTAssertEqual(diagnostic.outputFailure, .outputTooLarge)
        XCTAssertEqual(diagnostic.stdoutBytes, 200_000)
        XCTAssertTrue(diagnostic.stdoutTruncated)
        XCTAssertLessThan(elapsed, 10, "draining a large payload must not hang")
    }

    func testRefresh_countsLargeStderrWithoutHanging() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-large-stderr",
            body: "#!/bin/bash\nyes E | head -c 200000 1>&2\nexit 4\n"
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        let start = Date()
        let error = try await capturedError(from: refresher)
        let elapsed = Date().timeIntervalSince(start)

        guard case let .processFailed(diagnostic) = error else {
            return XCTFail("Expected processFailed, got \(error)")
        }
        XCTAssertEqual(diagnostic.stderrBytes, 200_000)
        XCTAssertEqual(diagnostic.exitStatus, 4)
        XCTAssertFalse(diagnostic.stdoutTruncated)
        XCTAssertLessThan(elapsed, 10, "draining a large stderr stream must not hang")
    }

    func testRefresh_descendantHoldingPipeDoesNotExtendRefresh() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-descendant",
            body: """
            #!/bin/bash
            ( sleep 10 ) &
            cat <<'JSON'
            {"is_error":false,"result":"\(usageText(session: 12, week: 34))"}
            JSON
            exit 0
            """
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        let start = Date()
        try await refresher.refresh()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 5, "a retained pipe must not delay the refresh")
        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 12)
        XCTAssertEqual(cache.rateLimits?.sevenDay?.usedPercentage, 34)
    }

    func testRefresh_leavesCacheUntouchedWhenOutputValidationFails() async throws {
        try StatuslineCacheStore(cacheURL: cacheURL).write(
            StatuslineCache(
                writtenAt: 1000,
                rateLimits: RateLimits(
                    fiveHour: Window(usedPercentage: 42, resetsAt: 2000),
                    sevenDay: nil
                )
            )
        )
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-banner",
            body: """
            #!/bin/bash
            cat <<'JSON'
            {"is_error":false,"result":"Claude Pro plan. Manage at claude.ai"}
            JSON
            """
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        _ = try? await refresher.refresh()

        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.writtenAt, 1000, "cache must be left exactly as it was")
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 42)
    }

    func testRefresh_acceptsInventoryLargerThan64KiB() async throws {
        let inventory = String(repeating: "A", count: 100_000)
        let payload = #"{"is_error":false,"result":"\#(usageText(session: 12, week: 34))","inventory":"\#(inventory)"}"#
        let payloadURL = tmpDir.appendingPathComponent("inventory-payload.json")
        try Data(payload.utf8).write(to: payloadURL)
        XCTAssertGreaterThan(payload.utf8.count, 64 * 1024)
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-inventory",
            body: "#!/bin/bash\ncat '\(payloadURL.path)'\n"
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        try await refresher.refresh()

        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 12)
        XCTAssertEqual(cache.rateLimits?.sevenDay?.usedPercentage, 34)
    }

    func testRefresh_inventorySentinelNeverReachesCacheOrLog() async throws {
        let sentinel = "SENTINEL_INVENTORY_9f3c"
        let errorLog = ErrorLog(directoryURL: tmpDir.appendingPathComponent("logs"))
        let payload = #"{"is_error":false,"result":"\#(usageText(session: 12, week: 34))","plugins":["\#(sentinel)"]}"#
        let payloadURL = tmpDir.appendingPathComponent("sentinel-payload.json")
        try Data(payload.utf8).write(to: payloadURL)
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-sentinel",
            body: "#!/bin/bash\ncat '\(payloadURL.path)'\n"
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path, errorLog: errorLog)

        try await refresher.refresh()

        let cache = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertFalse(cache.contains(sentinel))
        XCTAssertFalse(FileManager.default.fileExists(atPath: errorLog.fileURL.path))
    }

    private func makeRefresher(
        binaryPath: String?,
        outputCaptureLimit: Int = SubprocessOutputCollector.captureLimit,
        errorLog: ErrorLog = .shared
    ) -> ClaudeCodeRefresher {
        ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: binaryPath),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL, errorLog: errorLog),
            spawnTimeout: 30,
            terminateGrace: 2,
            spawnDebounce: 60,
            outputCaptureLimit: outputCaptureLimit
        )
    }

    private func capturedError(from refresher: ClaudeCodeRefresher) async throws -> ClaudeCodeRefresherError {
        do {
            try await refresher.refresh()
        } catch let error as ClaudeCodeRefresherError {
            return error
        }
        XCTFail("Expected the refresh to fail")
        struct UnexpectedSuccess: Error {}
        throw UnexpectedSuccess()
    }

    private func usageText(session: Int, week: Int) -> String {
        let line1 = "Current session: \(session)% used · resets Jul 21 at 12:59am (Europe/Berlin)"
        let line2 = "Current week (all models): \(week)% used · resets Jul 24 at 5:59am (Europe/Berlin)"
        return "\(line1)\\n\(line2)"
    }

    private func writeFakeBinary(name: String, body: String) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }
}
