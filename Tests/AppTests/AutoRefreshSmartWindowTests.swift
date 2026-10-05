@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class AutoRefreshSmartWindowTests: XCTestCase {
    private let suiteName = "filbert.tests.auto-refresh-smart-window"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(defaults)
        AutoRefreshPreferences.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(.standard)
        AutoRefreshPreferences.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testFastModeEndsByElapsedTimeRegardlessOfFastInterval() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
        AutoRefreshPreferences.quietWindow = 5 * 60
        let clock = TestElapsedClock()
        let provider = RefreshSpyProvider()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            elapsed: { clock.elapsed() },
            boundarySleeper: { _ in throw CancellationError() }
        )

        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        provider.percentage = 20
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)

        AutoRefreshPreferences.fastInterval = 10
        clock.advance(by: 5 * 60 - 1)
        viewModel.syncFastRefreshStatuses()
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)

        clock.advance(by: 1)
        viewModel.syncFastRefreshStatuses()
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .cooldown)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))

        clock.advance(by: 5 * 60)
        viewModel.syncFastRefreshStatuses()
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
    }

    func testPhaseBoundaryTimerArmsForTheQuietWindow() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
        AutoRefreshPreferences.quietWindow = 5 * 60
        let provider = RefreshSpyProvider()
        let boundaryRecorder = IntervalRecorder()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            elapsed: { 0 },
            boundarySleeper: { interval in
                await boundaryRecorder.record(interval)
                throw CancellationError()
            }
        )

        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        provider.percentage = 20
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        await waitForIntervals(on: boundaryRecorder, count: 1)
        let intervals = await boundaryRecorder.intervals()
        XCTAssertEqual(intervals.first, 5 * 60)
    }
}
