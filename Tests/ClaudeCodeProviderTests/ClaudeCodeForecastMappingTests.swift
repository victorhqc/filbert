@testable import ClaudeCodeProvider
import Core
import Foundation
import XCTest

final class ClaudeCodeForecastMappingTests: XCTestCase {
    private let now = Date().timeIntervalSince1970.rounded()
    private var fiveHourReset: TimeInterval {
        now + 3 * 60 * 60
    }

    private var weeklyReset: TimeInterval {
        now + 4 * 24 * 60 * 60
    }

    func testWindowsMapToFixedPeriodDescriptors() async throws {
        let quota = try await fetchQuota(StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 42, resetsAt: fiveHourReset, writtenAt: now - 30),
                sevenDay: Window(usedPercentage: 60, resetsAt: weeklyReset, writtenAt: now - 60)
            )
        ))

        XCTAssertEqual(quota.activityObservation?.metrics.map(\.forecastDescriptor), [
            descriptor(lineId: "five-hour-usage", resetsAt: fiveHourReset, writtenAt: now - 30),
            descriptor(lineId: "weekly-usage", resetsAt: weeklyReset, writtenAt: now - 60),
        ])
    }

    func testTimingFallsBackToTheCacheWriteTime() async throws {
        let quota = try await fetchQuota(StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(fiveHour: Window(usedPercentage: 42, resetsAt: fiveHourReset), sevenDay: nil)
        ))

        XCTAssertEqual(
            quota.activityObservation?.metrics.first?.forecastDescriptor?.timing,
            .source(Date(timeIntervalSince1970: now))
        )
    }

    func testAWindowWithoutAResetHasNoDescriptor() async throws {
        let quota = try await fetchQuota(StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(fiveHour: Window(usedPercentage: 0), sevenDay: nil)
        ))

        let metric = try XCTUnwrap(quota.activityObservation?.metrics.first)
        XCTAssertEqual(metric.value, .number(0))
        XCTAssertNil(metric.forecastDescriptor)
    }

    func testLinesShareMetricIdsAndOneLimitGroup() async throws {
        let quota = try await fetchQuota(bothWindows())

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "weekly-usage"])
        XCTAssertEqual(quota.lines.map(\.id), quota.activityObservation?.metrics.map(\.id))
        XCTAssertEqual(quota.lines.map(\.limitGroup), ["subscription", "subscription"])
    }

    func testTheHeadlineSummarizesTheFiveHourWindow() async throws {
        let quota = try await fetchQuota(bothWindows())

        XCTAssertEqual(quota.headlineUsageLineId, "five-hour-usage")
    }

    func testTheHeadlineFallsBackToTheWeeklyWindow() async throws {
        let quota = try await fetchQuota(StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(fiveHour: nil, sevenDay: Window(usedPercentage: 60, resetsAt: weeklyReset))
        ))

        XCTAssertEqual(quota.headlineUsageLineId, "weekly-usage")
    }

    func testAWriteWithoutWindowsNamesNoHeadlineLine() async throws {
        let quota = try await fetchQuota(StatuslineCache(writtenAt: now, rateLimits: nil))

        XCTAssertNil(quota.headlineUsageLineId)
        XCTAssertEqual(quota.activityObservation?.metrics, [])
    }

    private func bothWindows() -> StatuslineCache {
        StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 42, resetsAt: fiveHourReset),
                sevenDay: Window(usedPercentage: 60, resetsAt: weeklyReset)
            )
        )
    }

    private func descriptor(
        lineId: String,
        resetsAt: TimeInterval,
        writtenAt: TimeInterval
    ) -> AllowanceForecastDescriptor {
        AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: 100, resetsAt: Date(timeIntervalSince1970: resetsAt)),
            unit: .percentagePoints,
            resolution: 1,
            timing: .source(Date(timeIntervalSince1970: writtenAt)),
            usageLineId: lineId
        )
    }

    private func fetchQuota(_ cache: StatuslineCache) async throws -> ProviderQuota {
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
