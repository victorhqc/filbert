@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeRefresherDebounceTests: XCTestCase {
    private var directory: URL!
    private var cacheURL: URL!
    private var countURL: URL!
    private var log: ErrorLog!
    private var store: StatuslineCacheStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-refresher-debounce-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("claude-code.json")
        countURL = directory.appendingPathComponent("spawns")
        log = ErrorLog(directoryURL: directory.appendingPathComponent("logs"))
        store = StatuslineCacheStore(cacheURL: cacheURL, errorLog: log)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSuccessfulRefreshRespawnsImmediatelyAfterCacheRemoval() async throws {
        let refresher = try makeRefresher()
        try await refresher.refresh()
        try assertUsage()
        XCTAssertEqual(try spawnCount(), 1)

        try FileManager.default.removeItem(at: cacheURL)
        try await refresher.refresh()

        try assertUsage()
        XCTAssertEqual(try spawnCount(), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
    }

    func testSuccessfulRefreshRespawnsWhenCacheHasNoPopulatedWindows() async throws {
        let emptyLimits: [RateLimits?] = [
            nil,
            RateLimits(fiveHour: nil, sevenDay: nil),
            RateLimits(fiveHour: Window(), sevenDay: Window()),
        ]
        for (index, limits) in emptyLimits.enumerated() {
            let refresher = try makeRefresher()
            try await refresher.refresh()
            try store.write(StatuslineCache(writtenAt: 1234, rateLimits: limits))

            try await refresher.refresh()

            try assertUsage()
            XCTAssertEqual(try spawnCount(), (index + 1) * 2)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
    }

    func testSuccessfulRefreshDebouncesWhileCacheRemainsUsable() async throws {
        let refresher = try makeRefresher()
        try await refresher.refresh()
        let original = try Data(contentsOf: cacheURL)

        try await refresher.refresh()

        XCTAssertEqual(try spawnCount(), 1)
        XCTAssertEqual(try Data(contentsOf: cacheURL), original)
        try assertUsage()
    }

    func testSuccessfulDebounceAcceptsEitherWindowAndPartialData() async throws {
        let usableLimits = [
            RateLimits(fiveHour: Window(usedPercentage: 0), sevenDay: nil),
            RateLimits(fiveHour: nil, sevenDay: Window(resetsAt: 1_900_000_000)),
        ]
        for (index, limits) in usableLimits.enumerated() {
            let refresher = try makeRefresher()
            try await refresher.refresh()
            try store.write(StatuslineCache(writtenAt: 1234, rateLimits: limits))
            let original = try Data(contentsOf: cacheURL)

            try await refresher.refresh()

            XCTAssertEqual(try spawnCount(), index + 1)
            XCTAssertEqual(try Data(contentsOf: cacheURL), original)
        }
    }

    func testMalformedCacheIsLoggedAndRepairedWithinSuccessfulDebounce() async throws {
        let refresher = try makeRefresher()
        try await refresher.refresh()
        try Data("PRIVATE_CACHE_CONTENT".utf8).write(to: cacheURL)

        try await refresher.refresh()

        try assertUsage()
        XCTAssertEqual(try spawnCount(), 2)
        let records = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertTrue(records.contains("cache-decode-failed"))
        XCTAssertFalse(records.contains("PRIVATE_CACHE_CONTENT"))
        XCTAssertFalse(records.contains(cacheURL.path))
    }

    func testUnreadableCacheIsLoggedAndReturnsRepairFailure() async throws {
        let refresher = try makeRefresher()
        try await refresher.refresh()
        try FileManager.default.removeItem(at: cacheURL)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        do {
            try await refresher.refresh()
            XCTFail("Expected cache write failure")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }

        XCTAssertEqual(try spawnCount(), 2)
        let records = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertTrue(records.contains("cache-read-failed"))
        XCTAssertFalse(records.contains(cacheURL.path))
    }

    func testFailedRefreshKeepsCooldownRegardlessOfCacheContents() async throws {
        let refresher = try makeRefresher(exitStatus: 7)
        try await assertProcessFailure(refresher)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        try await assertProcessFailure(refresher)

        try store.write(StatuslineCache(
            writtenAt: 1234,
            rateLimits: RateLimits(fiveHour: Window(usedPercentage: 12), sevenDay: nil)
        ))
        try await assertProcessFailure(refresher)
        try Data("PRIVATE_CACHE_CONTENT".utf8).write(to: cacheURL)
        try await assertProcessFailure(refresher)

        XCTAssertEqual(try spawnCount(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
    }

    func testConcurrentRefreshesAfterCacheRemovalAwaitOneRepairSpawn() async throws {
        let refresher = try makeRefresher(delay: 0.2)
        try await refresher.refresh()
        try FileManager.default.removeItem(at: cacheURL)

        async let first: Void = refreshAndAssertUsage(refresher)
        async let second: Void = refreshAndAssertUsage(refresher)
        _ = try await (first, second)

        XCTAssertEqual(try spawnCount(), 2)
    }

    private func makeRefresher(exitStatus: Int = 0, delay: Double = 0) throws -> ClaudeCodeRefresher {
        let binaryURL = directory.appendingPathComponent("fake-claude")
        let script = """
        #!/bin/sh
        printf 'spawn\\n' >> "\(countURL.path)"
        sleep \(delay)
        printf '%s\\n' '{"result":"Current session: 12% used\\nCurrent week (all models): 34% used"}'
        exit \(exitStatus)
        """
        try script.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        let workingDirectory = try XCTUnwrap(directory)
        return ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: binaryURL.path),
            cacheStore: store,
            spawnTimeout: 5,
            terminateGrace: 0.1,
            spawnDebounce: 3600,
            workingDirectoryProvider: { workingDirectory }
        )
    }

    private func spawnCount() throws -> Int {
        try String(contentsOf: countURL, encoding: .utf8).split(separator: "\n").count
    }

    private func assertUsage(file: StaticString = #filePath, line: UInt = #line) throws {
        let cache = try XCTUnwrap(store.readForQuota(), file: file, line: line)
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 12, file: file, line: line)
        XCTAssertEqual(cache.rateLimits?.sevenDay?.usedPercentage, 34, file: file, line: line)
    }

    private func refreshAndAssertUsage(_ refresher: ClaudeCodeRefresher) async throws {
        try await refresher.refresh()
        try assertUsage()
    }

    private func assertProcessFailure(_ refresher: ClaudeCodeRefresher) async throws {
        do {
            try await refresher.refresh()
            XCTFail("Expected process failure")
        } catch let error as ClaudeCodeRefresherError {
            guard case let .processFailed(diagnostic) = error else {
                return XCTFail("Expected processFailed, got \(error)")
            }
            XCTAssertEqual(diagnostic.exitStatus, 7)
        }
    }
}
