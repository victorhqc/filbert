@testable import ClaudeCodeProvider
import Core
import Foundation
import XCTest

final class ClaudeCodeActivityObservationTests: XCTestCase {
    func testFetchQuotaMapsOnlyConsumptionIntoActivityObservation() async throws {
        let quota = try await fetchQuota(
            writtenAt: Date().timeIntervalSince1970,
            fiveHour: 42,
            sevenDay: 60
        )

        XCTAssertNil(quota.activityObservation?.availability)
        XCTAssertEqual(quota.activityObservation?.freshness, .fresh)
        XCTAssertEqual(metricsWithoutDescriptors(quota), [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(42)),
            ProviderActivityMetric(id: "weekly-usage", kind: .usage, value: .number(60)),
        ])
        XCTAssertEqual(quota.lines[0].windowDuration, UsageWindowDuration.fiveHours)
        XCTAssertEqual(quota.lines[1].windowDuration, UsageWindowDuration.week)
    }

    func testFetchQuotaPreservesFractionalCachePercentage() async throws {
        let quota = try await fetchQuota(
            writtenAt: Date().timeIntervalSince1970,
            fiveHour: 42.5,
            sevenDay: nil
        )

        XCTAssertEqual(metricsWithoutDescriptors(quota), [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(Decimal(42.5))),
        ])
    }

    func testFetchQuotaStaleCacheIsMarkedStaleAndKeepsMetrics() async throws {
        let writtenAt = Date().timeIntervalSince1970 - ClaudeCodeProvider.freshnessThreshold - 60
        let quota = try await fetchQuota(writtenAt: writtenAt, fiveHour: 42, sevenDay: nil)

        XCTAssertEqual(quota.activityObservation?.freshness, .stale)
        XCTAssertEqual(metricsWithoutDescriptors(quota), [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(42)),
        ])
    }

    func testFetchQuotaExcludesAStaleCarriedWindowFromAFreshObservation() async throws {
        let now = Date().timeIntervalSince1970
        let staleWrite = now - ClaudeCodeProvider.freshnessThreshold - 60
        let quota = try await fetchQuota(cache: StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 42, resetsAt: 1_713_127_600, writtenAt: now),
                sevenDay: Window(usedPercentage: 60, resetsAt: 1_713_500_000, writtenAt: staleWrite)
            )
        ))

        XCTAssertEqual(quota.activityObservation?.freshness, .fresh)
        XCTAssertEqual(metricsWithoutDescriptors(quota), [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(42)),
        ])
    }

    func testMergeAndWriteCacheKeepsACarriedWindowTimestamp() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let cacheStore = StatuslineCacheStore(
            cacheURL: temporaryDirectory.appendingPathComponent("claude-code.json")
        )
        let staleWrite = Date().timeIntervalSince1970 - ClaudeCodeProvider.freshnessThreshold - 60
        try cacheStore.write(StatuslineCache(
            writtenAt: staleWrite,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 10, resetsAt: 1, writtenAt: staleWrite),
                sevenDay: Window(usedPercentage: 20, resetsAt: 2, writtenAt: staleWrite)
            )
        ))

        let before = Date().timeIntervalSince1970
        try ClaudeCodeRefresher.mergeAndWriteCache(
            windows: [
                ClaudeCodeRefresher.ParsedWindow(
                    slot: .fiveHour,
                    window: Window(usedPercentage: 11, resetsAt: 3)
                ),
            ],
            into: cacheStore
        )
        let after = Date().timeIntervalSince1970

        let cache = try XCTUnwrap(cacheStore.read())
        XCTAssertEqual(cache.rateLimits?.fiveHour?.usedPercentage, 11)
        let fiveHourWrittenAt = try XCTUnwrap(cache.rateLimits?.fiveHour?.writtenAt)
        XCTAssertGreaterThanOrEqual(fiveHourWrittenAt, before)
        XCTAssertLessThanOrEqual(fiveHourWrittenAt, after)
        XCTAssertEqual(cache.rateLimits?.sevenDay?.usedPercentage, 20)
        XCTAssertEqual(cache.rateLimits?.sevenDay?.writtenAt, staleWrite)
    }

    private func metricsWithoutDescriptors(_ quota: ProviderQuota) -> [ProviderActivityMetric]? {
        quota.activityObservation?.metrics.map { ProviderActivityMetric(id: $0.id, kind: $0.kind, value: $0.value) }
    }

    private func fetchQuota(
        writtenAt: TimeInterval,
        fiveHour: Double?,
        sevenDay: Double?
    ) async throws -> ProviderQuota {
        try await fetchQuota(cache: StatuslineCache(
            writtenAt: writtenAt,
            rateLimits: RateLimits(
                fiveHour: fiveHour.map { Window(usedPercentage: $0, resetsAt: 1_713_127_600) },
                sevenDay: sevenDay.map { Window(usedPercentage: $0, resetsAt: 1_713_500_000) }
            )
        ))
    }

    private func fetchQuota(cache: StatuslineCache) async throws -> ProviderQuota {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let cacheStore = StatuslineCacheStore(
            cacheURL: temporaryDirectory.appendingPathComponent("claude-code.json")
        )
        try cacheStore.write(cache)

        return try await ClaudeCodeProvider(cacheStore: cacheStore).fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )
    }
}
