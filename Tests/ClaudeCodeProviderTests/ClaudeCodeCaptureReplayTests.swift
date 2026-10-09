@testable import ClaudeCodeProvider
import Core
import Foundation
import XCTest

final class ClaudeCodeCaptureReplayTests: XCTestCase {
    private struct Read {
        let cache: StatuslineCache
        let metrics: [ProviderActivityMetric]
    }

    func testTheUsageOnlyCaptureNeverDecreasesInsideAPeriod() async throws {
        let reads = try await replay("claude-code-cache-usage-only", sharingOneProvider: true)

        let periods = periodFirstResets(in: reads)

        XCTAssertEqual(periods[ClaudeCodeProvider.fiveHourLineId], [1_791_549_540, 1_791_567_600])
        XCTAssertEqual(periods[ClaudeCodeProvider.weeklyLineId], [1_791_543_600, 1_792_148_400])
    }

    func testTheTerminalCaptureNeverDecreasesInsideAPeriod() async throws {
        let reads = try await replay("claude-code-cache-terminal", sharingOneProvider: true)

        let periods = periodFirstResets(in: reads)

        XCTAssertEqual(periods[ClaudeCodeProvider.fiveHourLineId], [1_791_567_540])
        XCTAssertEqual(periods[ClaudeCodeProvider.weeklyLineId], [1_792_148_340])
    }

    func testTheTerminalCaptureKeepsItsFiveHourRate() async throws {
        let reads = try await replay("claude-code-cache-terminal", sharingOneProvider: true)

        let afterFirstRate = try XCTUnwrap(statesAfterFirstRate(fiveHourStates(in: reads)))

        XCTAssertFalse(afterFirstRate.contains(.learning))
    }

    func testWithoutTheMemoryTheTerminalCaptureRestartsAfterItsFirstRate() async throws {
        let reads = try await replay("claude-code-cache-terminal", sharingOneProvider: false)

        let afterFirstRate = try XCTUnwrap(statesAfterFirstRate(fiveHourStates(in: reads)))

        XCTAssertTrue(afterFirstRate.contains(.learning))
    }

    private func replay(_ fixture: String, sharingOneProvider: Bool) async throws -> [Read] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json"))
        let caches = try JSONDecoder().decode([StatuslineCache].self, from: Data(contentsOf: url))
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let cacheStore = StatuslineCacheStore(
            cacheURL: temporaryDirectory.appendingPathComponent("claude-code.json")
        )
        let sharedProvider = ClaudeCodeProvider(cacheStore: cacheStore)

        var reads: [Read] = []
        for cache in caches {
            try cacheStore.write(cache)
            let provider = sharingOneProvider ? sharedProvider : ClaudeCodeProvider(cacheStore: cacheStore)
            let quota = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: ClaudeCodeProvider.baseURL)
            reads.append(Read(cache: cache, metrics: quota.activityObservation?.metrics ?? []))
        }
        return reads
    }

    /// Fails on any decrease inside a period, which Core would read as a correction.
    private func periodFirstResets(in reads: [Read]) -> [String: [TimeInterval]] {
        var firstResets: [String: Date] = [:]
        var latestValues: [String: Decimal] = [:]
        var periods: [String: [TimeInterval]] = [:]
        for read in reads {
            for metric in read.metrics {
                guard case let .number(value) = metric.value,
                      case let .fixedPeriod(_, resetsAt)? = metric.forecastDescriptor?.accounting
                else {
                    firstResets[metric.id] = nil
                    continue
                }
                let continuesPeriod = firstResets[metric.id].map {
                    AllowanceForecastDescriptor.isSamePeriod(resetsAt: resetsAt, periodResetsAt: $0)
                } ?? false
                if continuesPeriod, let latest = latestValues[metric.id] {
                    XCTAssertGreaterThanOrEqual(value, latest, "\(metric.id) at \(read.cache.writtenAt)")
                } else {
                    firstResets[metric.id] = resetsAt
                    periods[metric.id, default: []].append(resetsAt.timeIntervalSince1970)
                }
                latestValues[metric.id] = value
            }
        }
        return periods
    }

    private func statesAfterFirstRate(_ states: [AllowanceForecast.State]) -> ArraySlice<AllowanceForecast.State>? {
        states.firstIndex(where: \.hasRate).map { states[$0...] }
    }

    private func fiveHourStates(in reads: [Read]) -> [AllowanceForecast.State] {
        var forecaster = AllowanceForecaster()
        return reads.compactMap { read in
            let now = Date(timeIntervalSince1970: read.cache.writtenAt)
            // The captured reads are hours old. They were fresh when written.
            let observation = ProviderActivityObservation(
                metrics: read.metrics,
                freshness: read.metrics.isEmpty ? .unknown : .fresh
            )
            forecaster.record(observation, isStale: false, for: ClaudeCodeProvider.providerId, at: now)
            return forecaster.forecasts(for: ClaudeCodeProvider.providerId, at: now)[
                ClaudeCodeProvider.fiveHourLineId
            ]?.state
        }
    }
}

private extension AllowanceForecast.State {
    var hasRate: Bool {
        switch self {
        case .estimated, .beyondReset: true
        case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient: false
        }
    }
}
