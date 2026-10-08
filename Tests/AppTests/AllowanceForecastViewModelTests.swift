@testable import App
import Core
import Foundation
import XCTest

final class AllowanceForecastViewModelTests: AllowanceForecastViewModelTestCase {
    func testGenericProviderObtainsAForecastFromAcceptedResultsWithoutExtraFetches() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)

        let presentation = try presentation(harness, at: minute(20))
        _ = try self.presentation(harness, at: minute(25))

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.value, "30%")
        XCTAssertEqual(headline.status, "About \(CoarseDurationFormatting.string(from: 140 * 60)) of use remaining")
        XCTAssertEqual(harness.provider.fetchCallCount, 5)
    }

    func testATimelineTickBeforeTheLatestSampleUsesTheCurrentTime() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)

        let presentation = try presentation(harness, at: minute(18))

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.status, "About \(CoarseDurationFormatting.string(from: 140 * 60)) of use remaining")
    }

    func testAForecastRowKeepsBudgetPaceAndCompactStatus() async throws {
        let harness = try makeHarness(resetsAt: minute(3 * 24 * 60))
        harness.provider.windowDuration = UsageWindowDuration.week
        harness.provider.headlineUsageLineId = nil
        await drive(harness, trace: steadyTrace)

        let quota = try loadedQuota(harness)
        let forecast = try XCTUnwrap(presentation(harness, at: minute(20)).rowLines["window"])
        let pace = try XCTUnwrap(BudgetPace(line: quota.lines[0], now: minute(20)))
        let withForecast = PacedUsageLineText(pace: pace, forecast: forecast)
        let withoutForecast = PacedUsageLineText(pace: pace, forecast: nil)

        XCTAssertEqual(withForecast.used, "30% used")
        XCTAssertEqual(withForecast.remainingTime, withoutForecast.remainingTime)
        XCTAssertEqual(withForecast.allowance, withoutForecast.allowance)
        XCTAssertEqual(
            withForecast.accessibilitySentences,
            withoutForecast.accessibilitySentences + [forecast.accessibilityLabel]
        )
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: minute(20)), pace.tier)
    }

    func testAFailedRefreshAddsNoSample() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)
        harness.clock.date = minute(25)
        let before = try presentation(harness, at: minute(25))

        harness.provider.consumed = 40
        harness.provider.fetchError = ForecastSpyFailure()
        harness.viewModel.manualRefresh(for: providerId)
        await waitForFetch(harness, count: 6)

        XCTAssertNotNil(harness.viewModel.refreshErrors[providerId])
        XCTAssertNotNil(before.headline)
        XCTAssertEqual(try presentation(harness, at: minute(25)), before)
    }

    func testStaleQuotaPausesTheForecast() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)

        harness.clock.date = minute(22)
        harness.provider.consumed = 31
        harness.provider.isStale = true
        harness.viewModel.manualRefresh(for: providerId)
        await waitForFetch(harness, count: 6)

        let presentation = try presentation(harness, at: minute(22))
        XCTAssertNil(presentation.headline)
        XCTAssertEqual(presentation.rowLines["window"]?.text, "Forecast paused until fresh data arrives")
    }
}
