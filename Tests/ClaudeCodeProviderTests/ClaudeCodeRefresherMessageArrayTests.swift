@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeRefresherMessageArrayTests: XCTestCase {
    private typealias Messages = SyntheticClaudeMessages

    private var tmpDir: URL!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-refresher-array-\(UUID().uuidString)")
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

    func testRefresh_writesCacheFromRepresentativeArrayBelow10KiB() async throws {
        let payload = try Messages.data([
            Messages.initMessage(),
            Messages.rateLimitEvent(),
            Messages.assistant(text: Messages.usageText(session: 12, week: 34)),
            Messages.result(text: Messages.usageText(session: 12, week: 34)),
        ])
        XCTAssertLessThan(payload.count, 10 * 1024)
        let refresher = try makeRefresher(printing: payload, outputCaptureLimit: 64 * 1024)

        try await refresher.refresh()

        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 12)
        XCTAssertEqual(cache.rateLimits?.sevenDay?.usedPercentage, 34)
    }

    func testRefresh_acceptsArrayWithInventoryLargerThan64KiB() async throws {
        let inventory = (0 ..< 4000).map { "synthetic_tool_\($0)" }
        let payload = try Messages.data([
            Messages.initMessage(report: Messages.suppliedReport(), inventory: inventory),
            Messages.result(text: "Claude Pro plan. Manage at claude.ai"),
        ])
        XCTAssertGreaterThan(payload.count, 64 * 1024)
        let refresher = try makeRefresher(printing: payload)

        try await refresher.refresh()

        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 54)
        XCTAssertEqual(cache.rateLimits?.sevenDay?.usedPercentage, 18)
    }

    func testRefresh_nonzeroExitWithUsableArrayRecordsProcessFailureAndShape() async throws {
        try writeExistingCache()
        let payload = try Messages.data([Messages.result(text: Messages.usageText(session: 12, week: 34))])
        let refresher = try makeRefresher(printing: payload, exitStatus: 2)

        let error = try await capturedError(from: refresher)

        guard case let .processFailed(diagnostic) = error else {
            return XCTFail("Expected processFailed, got \(error)")
        }
        XCTAssertEqual(diagnostic.exitStatus, 2)
        XCTAssertEqual(diagnostic.stdoutJSONShape, .array)
        XCTAssertEqual(diagnostic.cliReportedError, false)
        XCTAssertNil(diagnostic.outputFailure)
        try assertExistingCacheUnchanged()
    }

    func testRefresh_malformedOutputOmitsShapeAndKeepsCache() async throws {
        try writeExistingCache()
        let refresher = try makeRefresher(printing: Data(#"[{"type":"result","result":"#.utf8))

        let error = try await capturedError(from: refresher)

        guard case let .noUsageData(diagnostic) = error else {
            return XCTFail("Expected noUsageData, got \(error)")
        }
        XCTAssertEqual(diagnostic.outputFailure, .invalidJSON)
        XCTAssertNil(diagnostic.stdoutJSONShape)
        try assertExistingCacheUnchanged()
    }

    func testRefresh_arrayFailureKeepsCacheAndPrivateContentOutOfLogAndError() async throws {
        try writeExistingCache()
        let sentinel = "SENTINEL_ARRAY_INVENTORY_7d21"
        let payload = try Messages.data([
            Messages.initMessage(report: Messages.report(session: 54), inventory: [sentinel]),
            Messages.assistant(text: sentinel),
        ])
        let refresher = try makeRefresher(printing: payload)

        let error = try await capturedError(from: refresher)

        guard case let .noUsageData(diagnostic) = error else {
            return XCTFail("Expected noUsageData, got \(error)")
        }
        XCTAssertEqual(diagnostic.outputFailure, .resultMissing)
        XCTAssertEqual(diagnostic.stdoutJSONShape, .array)
        XCTAssertFalse(error.localizedDescription.contains(sentinel))
        try assertExistingCacheUnchanged()
        XCTAssertFalse(try String(contentsOf: cacheURL, encoding: .utf8).contains(sentinel))

        let log = ErrorLog(directoryURL: tmpDir.appendingPathComponent("logs"))
        XCTAssertTrue(log.record(
            component: "app", operation: "proactive-refresh", code: "operation-failed",
            providerID: "claude-code", error: error
        ))
        let record = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertFalse(record.contains(sentinel))
        XCTAssertFalse(record.contains("init"))
        XCTAssertTrue(record.contains(#""stdoutJSONShape":"array""#))
        XCTAssertTrue(record.contains(#""outputFailure":"result-missing""#))
    }

    private func makeRefresher(
        printing payload: Data,
        exitStatus: Int32 = 0,
        outputCaptureLimit: Int = SubprocessOutputCollector.captureLimit
    ) throws -> ClaudeCodeRefresher {
        let payloadURL = tmpDir.appendingPathComponent("payload-\(UUID().uuidString).json")
        try payload.write(to: payloadURL)
        let binaryURL = tmpDir.appendingPathComponent("fake-claude-\(UUID().uuidString)")
        try "#!/bin/bash\ncat '\(payloadURL.path)'\nexit \(exitStatus)\n"
            .write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        return ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: binaryURL.path),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
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

    private func writeExistingCache() throws {
        try StatuslineCacheStore(cacheURL: cacheURL).write(StatuslineCache(
            writtenAt: 1000,
            rateLimits: RateLimits(fiveHour: Window(usedPercentage: 42, resetsAt: 2000), sevenDay: nil)
        ))
    }

    private func assertExistingCacheUnchanged() throws {
        let cache = try XCTUnwrap(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertEqual(cache.writtenAt, 1000)
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 42)
        XCTAssertNil(cache.rateLimits?.sevenDay)
    }
}
