@testable import ClaudeCodeProvider
import Core
import Foundation
import XCTest

final class ClaudeCodeWindowPeaksTests: XCTestCase {
    private let fiveHourReset: TimeInterval = 1_800_000_000
    private let weeklyReset: TimeInterval = 1_800_400_000

    func testALowerStatuslineReadingKeepsTheUsageValue() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 7, resetsAt: fiveHourReset), 7)
        XCTAssertEqual(fiveHour(peaks, 6, resetsAt: fiveHourReset), 7)
    }

    func testAHigherUsageReadingRaisesTheValue() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 6, resetsAt: fiveHourReset), 6)
        XCTAssertEqual(fiveHour(peaks, 7, resetsAt: fiveHourReset), 7)
        XCTAssertEqual(fiveHour(peaks, 6, resetsAt: fiveHourReset), 7)
    }

    func testAOneMinuteResetFlipStaysInThePeriod() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 7, resetsAt: fiveHourReset + 60), 7)
        XCTAssertEqual(fiveHour(peaks, 6, resetsAt: fiveHourReset), 7)
        XCTAssertEqual(fiveHour(peaks, 6, resetsAt: fiveHourReset + 60), 7)
    }

    func testAResetBeyondTheToleranceStartsANewPeriod() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 26, resetsAt: fiveHourReset), 26)
        XCTAssertEqual(fiveHour(peaks, 0, resetsAt: fiveHourReset + 5 * 60 * 60), 0)
    }

    func testResetsAreComparedWithTheFirstResetOfThePeriod() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 10, resetsAt: fiveHourReset), 10)
        XCTAssertEqual(fiveHour(peaks, 9, resetsAt: fiveHourReset + 200), 10)
        XCTAssertEqual(fiveHour(peaks, 8, resetsAt: fiveHourReset + 400), 8)
    }

    func testAWindowWithoutAResetStartsANewPeriod() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 26, resetsAt: fiveHourReset), 26)
        XCTAssertEqual(fiveHour(peaks, 0, resetsAt: nil), 0)
        XCTAssertEqual(fiveHour(peaks, 1, resetsAt: fiveHourReset + 60), 1)
        XCTAssertEqual(fiveHour(peaks, 0, resetsAt: fiveHourReset + 60), 1)
    }

    func testAWriteWithoutWindowsLeavesThePeaks() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 7, resetsAt: fiveHourReset), 7)
        XCTAssertNil(peaks.peaked(nil))
        XCTAssertEqual(fiveHour(peaks, 6, resetsAt: fiveHourReset), 7)
    }

    func testAWindowWithoutAPercentageLeavesThePeak() {
        let peaks = ClaudeCodeWindowPeaks()

        XCTAssertEqual(fiveHour(peaks, 7, resetsAt: fiveHourReset), 7)
        XCTAssertNil(fiveHour(peaks, nil, resetsAt: fiveHourReset))
        XCTAssertEqual(fiveHour(peaks, 6, resetsAt: fiveHourReset), 7)
    }

    func testWindowsKeepSeparatePeaks() {
        let peaks = ClaudeCodeWindowPeaks()

        _ = peaks.peaked(RateLimits(
            fiveHour: Window(usedPercentage: 7, resetsAt: fiveHourReset),
            sevenDay: Window(usedPercentage: 3, resetsAt: weeklyReset)
        ))
        let peaked = peaks.peaked(RateLimits(
            fiveHour: Window(usedPercentage: 6, resetsAt: fiveHourReset),
            sevenDay: nil
        ))
        let weekly = peaks.peaked(RateLimits(
            fiveHour: nil,
            sevenDay: Window(usedPercentage: 2, resetsAt: weeklyReset)
        ))

        XCTAssertEqual(peaked?.fiveHour?.usedPercentage, 7)
        XCTAssertNil(peaked?.sevenDay)
        XCTAssertEqual(weekly?.sevenDay?.usedPercentage, 3)
        XCTAssertNil(weekly?.fiveHour)
    }

    func testAPeakedWindowKeepsItsOwnResetAndTimestamp() {
        let peaks = ClaudeCodeWindowPeaks()
        _ = fiveHour(peaks, 7, resetsAt: fiveHourReset)

        let peaked = peaks.peaked(RateLimits(
            fiveHour: Window(usedPercentage: 6, resetsAt: fiveHourReset + 60, writtenAt: 1_799_990_000),
            sevenDay: nil
        ))?.fiveHour

        XCTAssertEqual(peaked?.usedPercentage, 7)
        XCTAssertEqual(peaked?.resetsAt, fiveHourReset + 60)
        XCTAssertEqual(peaked?.writtenAt, 1_799_990_000)
    }

    func testFetchQuotaReportsThePeakInTheLineHeadlineAndMetric() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let cacheStore = StatuslineCacheStore(
            cacheURL: temporaryDirectory.appendingPathComponent("claude-code.json")
        )
        let provider = ClaudeCodeProvider(cacheStore: cacheStore)
        let resetsAt = Date().addingTimeInterval(3600).timeIntervalSince1970
        let now = Date().timeIntervalSince1970

        try cacheStore.write(StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 7, resetsAt: resetsAt, writtenAt: now),
                sevenDay: nil
            )
        ))
        _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: ClaudeCodeProvider.baseURL)
        try cacheStore.write(StatuslineCache(
            writtenAt: now + 1,
            rateLimits: RateLimits(fiveHour: Window(usedPercentage: 6, resetsAt: resetsAt), sevenDay: nil)
        ))
        let quota = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: ClaudeCodeProvider.baseURL)

        XCTAssertEqual(quota.lines.first?.percentage, 7)
        XCTAssertTrue(quota.headline.hasPrefix("7%"))
        let metric = try XCTUnwrap(quota.activityObservation?.metrics.first)
        XCTAssertEqual(metric.value, .number(7))
        XCTAssertEqual(metric.forecastDescriptor?.timing, .source(Date(timeIntervalSince1970: now + 1)))
    }

    private func fiveHour(_ peaks: ClaudeCodeWindowPeaks, _ percentage: Double?, resetsAt: TimeInterval?) -> Double? {
        peaks.peaked(RateLimits(
            fiveHour: Window(usedPercentage: percentage, resetsAt: resetsAt),
            sevenDay: nil
        ))?.fiveHour?.usedPercentage
    }
}
