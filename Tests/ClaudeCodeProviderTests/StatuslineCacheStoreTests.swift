@testable import ClaudeCodeProvider
import Core
import XCTest

final class StatuslineCacheStoreTests: XCTestCase {
    private var cacheURL: URL!
    private var store: StatuslineCacheStore!
    private var log: ErrorLog!

    override func setUp() {
        super.setUp()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true
        )
        cacheURL = tmpDir.appendingPathComponent("claude-code.json")
        log = ErrorLog(directoryURL: tmpDir.appendingPathComponent("logs"))
        store = StatuslineCacheStore(cacheURL: cacheURL, errorLog: log)
    }

    override func tearDown() {
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
        }
        cacheURL = nil
        store = nil
        super.tearDown()
    }

    // MARK: - both windows present

    func testRead_decodesBothWindows() throws {
        let cache = makeCache(
            fiveHourPct: 42, fiveHourReset: 1_713_127_600,
            sevenDayPct: 60, sevenDayReset: 1_713_500_000
        )
        try store.write(cache)

        let decoded = store.read()
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.writtenAt, 1_713_000_000)
        XCTAssertEqual(decoded?.rateLimits?.fiveHour?.usedPercentage, 42)
        XCTAssertEqual(decoded?.rateLimits?.fiveHour?.resetsAt, 1_713_127_600)
        XCTAssertEqual(decoded?.rateLimits?.sevenDay?.usedPercentage, 60)
        XCTAssertEqual(decoded?.rateLimits?.sevenDay?.resetsAt, 1_713_500_000)
    }

    // MARK: - only five_hour

    func testRead_decodesOnlyFiveHour() throws {
        let cache = makeCache(
            fiveHourPct: 15, fiveHourReset: 1_713_127_600,
            sevenDayPct: nil, sevenDayReset: nil
        )
        try store.write(cache)

        let decoded = store.read()
        XCTAssertEqual(decoded?.rateLimits?.fiveHour?.usedPercentage, 15)
        XCTAssertNil(decoded?.rateLimits?.sevenDay)
    }

    // MARK: - only seven_day

    func testRead_decodesOnlySevenDay() throws {
        let cache = makeCache(
            fiveHourPct: nil, fiveHourReset: nil,
            sevenDayPct: 80, sevenDayReset: 1_713_500_000
        )
        try store.write(cache)

        let decoded = store.read()
        XCTAssertNil(decoded?.rateLimits?.fiveHour)
        XCTAssertEqual(decoded?.rateLimits?.sevenDay?.usedPercentage, 80)
    }

    // MARK: - no rate_limits (free-tier / new session)

    func testRead_decodesNilRateLimits() throws {
        let json = Data("""
        {
          "written_at": 1713000000
        }
        """.utf8)
        try json.write(to: cacheURL, options: .atomic)

        let decoded = store.read()
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.rateLimits)
    }

    // MARK: - absent file returns nil

    func testRead_returnsNilWhenFileAbsent() {
        XCTAssertNil(store.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
    }

    func testMalformedCacheThrowsForQuotaAndLogsOnlyWhenSuppressed() throws {
        try Data("SENTINEL_PRIVATE not-json".utf8).write(to: cacheURL)
        XCTAssertThrowsError(try store.readForQuota()) { error in
            XCTAssertEqual(error as? StatuslineCacheError, .decodeFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
        XCTAssertNil(store.read())
        let records = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertEqual(records.split(separator: "\n").count, 1)
        XCTAssertTrue(records.contains("cache-decode-failed"))
        XCTAssertFalse(records.contains("SENTINEL_PRIVATE"))
    }

    func testUnreadableExistingCacheIsNotMissingData() throws {
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.readForQuota()) { error in
            XCTAssertEqual(error as? StatuslineCacheError, .readFailed)
        }
        XCTAssertNil(store.read())
        let records = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertTrue(records.contains("cache-read-failed"))
        XCTAssertEqual(records.split(separator: "\n").count, 1)
    }

    // MARK: - Round-trip

    func testWriteThenRead_roundtripsCorrectly() throws {
        let cache = makeCache(
            fiveHourPct: 42, fiveHourReset: 1_713_127_600,
            sevenDayPct: 60, sevenDayReset: 1_713_500_000
        )
        try store.write(cache)

        let decoded = store.read()
        XCTAssertEqual(decoded?.writtenAt, 1_713_000_000)
        XCTAssertEqual(decoded?.rateLimits?.fiveHour?.usedPercentage, 42)
        XCTAssertEqual(decoded?.rateLimits?.sevenDay?.usedPercentage, 60)
    }

    // MARK: - atomic write (temp + rename)

    func testAtomicWrite_doesNotLeavePartialFile() throws {
        let original = makeCache(
            fiveHourPct: 10, fiveHourReset: 1,
            sevenDayPct: nil, sevenDayReset: nil
        )
        try store.write(original)

        let originalData = try Data(contentsOf: cacheURL)

        let updated = makeCache(
            fiveHourPct: 99, fiveHourReset: 2,
            sevenDayPct: nil, sevenDayReset: nil
        )
        try store.write(updated)

        let updatedData = try Data(contentsOf: cacheURL)
        XCTAssertNotEqual(originalData, updatedData)

        let decoded = store.read()
        XCTAssertEqual(decoded?.rateLimits?.fiveHour?.usedPercentage, 99)
    }

    // MARK: - Helpers

    private func makeCache(
        fiveHourPct: Double?,
        fiveHourReset: TimeInterval?,
        sevenDayPct: Double?,
        sevenDayReset: TimeInterval?
    ) -> StatuslineCache {
        let fiveHour: Window? = if let pct = fiveHourPct, let reset = fiveHourReset {
            Window(usedPercentage: pct, resetsAt: reset)
        } else {
            nil
        }

        let sevenDay: Window? = if let pct = sevenDayPct, let reset = sevenDayReset {
            Window(usedPercentage: pct, resetsAt: reset)
        } else {
            nil
        }

        let rateLimits: RateLimits? = if fiveHour != nil || sevenDay != nil {
            RateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
        } else {
            nil
        }

        return StatuslineCache(
            writtenAt: 1_713_000_000,
            rateLimits: rateLimits
        )
    }
}
