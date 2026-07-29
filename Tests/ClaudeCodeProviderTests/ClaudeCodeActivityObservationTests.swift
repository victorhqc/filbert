@testable import ClaudeCodeProvider
import Core
import Foundation
import XCTest

final class ClaudeCodeActivityObservationTests: XCTestCase {
    func testFetchQuotaMapsOnlyConsumptionIntoActivityObservation() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let cacheURL = temporaryDirectory.appendingPathComponent("claude-code.json")
        let cacheStore = StatuslineCacheStore(cacheURL: cacheURL)
        try cacheStore.write(StatuslineCache(
            writtenAt: Date().timeIntervalSince1970,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 42, resetsAt: 1_713_127_600),
                sevenDay: Window(usedPercentage: 60, resetsAt: 1_713_500_000)
            )
        ))

        let quota = try await ClaudeCodeProvider(cacheStore: cacheStore).fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertNil(quota.activityObservation?.availability)
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "five-hour-usage", kind: .usage, value: .number(42)),
            ProviderActivityMetric(id: "weekly-usage", kind: .usage, value: .number(60)),
        ])
    }
}
