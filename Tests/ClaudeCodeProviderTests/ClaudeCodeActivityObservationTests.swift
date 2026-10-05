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
        XCTAssertEqual(quota.activityObservation?.metrics, [
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

        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(Decimal(42.5))),
        ])
    }

    func testFetchQuotaStaleCacheIsMarkedStaleAndKeepsMetrics() async throws {
        let writtenAt = Date().timeIntervalSince1970 - ClaudeCodeProvider.freshnessThreshold - 60
        let quota = try await fetchQuota(writtenAt: writtenAt, fiveHour: 42, sevenDay: nil)

        XCTAssertEqual(quota.activityObservation?.freshness, .stale)
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(42)),
        ])
    }

    private func fetchQuota(
        writtenAt: TimeInterval,
        fiveHour: Double?,
        sevenDay: Double?
    ) async throws -> ProviderQuota {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let cacheStore = StatuslineCacheStore(
            cacheURL: temporaryDirectory.appendingPathComponent("claude-code.json")
        )
        try cacheStore.write(StatuslineCache(
            writtenAt: writtenAt,
            rateLimits: RateLimits(
                fiveHour: fiveHour.map { Window(usedPercentage: $0, resetsAt: 1_713_127_600) },
                sevenDay: sevenDay.map { Window(usedPercentage: $0, resetsAt: 1_713_500_000) }
            )
        ))

        return try await ClaudeCodeProvider(cacheStore: cacheStore).fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )
    }
}
