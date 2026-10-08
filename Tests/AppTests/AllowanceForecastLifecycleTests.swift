@testable import App
import AppKit
import Core
import Foundation
import XCTest

final class AllowanceForecastLifecycleTests: AllowanceForecastViewModelTestCase {
    private let paused = "Forecast paused until fresh data arrives"
    private let learning = "Learning your usage rate…"

    func testSleepPausesTheForecast() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)

        harness.viewModel.handleActivityWillSleep()

        let presentation = try presentation(harness, at: minute(21))
        XCTAssertNil(presentation.headline)
        XCTAssertEqual(presentation.rowLines["window"]?.text, paused)
    }

    func testWakeObserverPausesTheForecastUntilASampleAfterTheWake() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)
        harness.clock.date = minute(21)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitForRowText(paused, harness, at: minute(21))

        XCTAssertEqual(rowText(harness, at: minute(21)), paused)
        XCTAssertNil(try presentation(harness, at: minute(21)).headline)

        harness.clock.date = minute(25)
        harness.provider.consumed = 33
        harness.viewModel.manualRefresh(for: providerId)
        await waitForFetch(harness, count: 6)

        XCTAssertEqual(rowText(harness, at: minute(25)), learning)
    }

    func testSystemClockObserverPausesTheForecast() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)
        harness.clock.date = minute(21)

        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        await waitForRowText(paused, harness, at: minute(21))

        XCTAssertEqual(rowText(harness, at: minute(21)), paused)
        XCTAssertNil(try presentation(harness, at: minute(21)).headline)
    }

    func testDisablingTheProviderClearsItsHistory() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: [(0, 20), (5, 23)])
        XCTAssertTrue(harness.viewModel.hasAllowanceForecasts(for: providerId))

        harness.viewModel.setProviderEnabled(false, for: providerId)

        XCTAssertFalse(harness.viewModel.hasAllowanceForecasts(for: providerId))
    }

    func testSavingAnOverrideURLStartsANewHistory() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)
        harness.clock.date = minute(22)
        harness.provider.consumed = 31

        try harness.viewModel.saveOverrideURL(URL(string: "https://proxy.example.com"), for: providerId)
        await waitForFetch(harness, count: 6)

        XCTAssertNil(try presentation(harness, at: minute(22)).headline)
        XCTAssertEqual(rowText(harness, at: minute(22)), learning)
    }

    func testImportingCredentialsStartsANewHistory() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)
        harness.clock.date = minute(22)
        harness.provider.consumed = 31

        await harness.viewModel.importCredentials(for: providerId)
        await waitForFetch(harness, count: 6)

        XCTAssertNil(try presentation(harness, at: minute(22)).headline)
        XCTAssertEqual(rowText(harness, at: minute(22)), learning)
    }

    func testDeletingTheKeyClearsTheHistory() async throws {
        let harness = try makeHarness()
        await drive(harness, trace: steadyTrace)
        XCTAssertTrue(harness.viewModel.hasAllowanceForecasts(for: providerId))

        try harness.viewModel.deleteKey(for: providerId)

        XCTAssertFalse(harness.viewModel.hasAllowanceForecasts(for: providerId))
    }
}

private extension AllowanceForecastLifecycleTests {
    func rowText(_ harness: ForecastHarness, at date: Date) -> String? {
        try? presentation(harness, at: date).rowLines["window"]?.text
    }

    /// Notification observers hop to the main actor in a new task.
    func waitForRowText(_ text: String, _ harness: ForecastHarness, at date: Date) async {
        for _ in 0 ..< 1000 {
            guard rowText(harness, at: date) != text else { return }
            await Task.yield()
        }
    }
}
