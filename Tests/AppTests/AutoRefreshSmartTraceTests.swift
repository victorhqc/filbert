@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class AutoRefreshSmartTraceTests: XCTestCase {
    private let suiteName = "filbert.tests.auto-refresh-smart-trace"
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

    func testManualHintDuringAnInFlightRequestDoesNotStartASecondRequest() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
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

        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertEqual(provider.fetchCallCount, 2)
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)
    }

    func testSemanticChangeInRegularModeStaysOnTheSlowInterval() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .regular
        let clock = TestElapsedClock()
        let provider = RefreshSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { interval in
                await recorder.record(interval)
                throw CancellationError()
            },
            elapsed: { clock.elapsed() },
            boundarySleeper: { _ in throw CancellationError() }
        )

        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        provider.percentage = 20
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
        await waitForIntervals(on: recorder, count: 2)
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, AutoRefreshPreferences.defaultSlowInterval)
    }

    func testMenuBarActivityScoresDoNotChangeRefreshCadence() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
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

        let date = Date(timeIntervalSinceReferenceDate: 5000)
        viewModel.recordActivityObservation(
            for: RefreshSpyProvider.providerId,
            observation: activity(usage: 10),
            at: date
        )
        viewModel.recordActivityObservation(
            for: RefreshSpyProvider.providerId,
            observation: activity(usage: 30),
            at: date
        )

        XCTAssertGreaterThan(
            viewModel.activityRuntime.policy.effectiveScore(for: RefreshSpyProvider.providerId, at: date),
            0
        )
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
    }

    func testFastRefreshMatchesSlowIntervalOnlyWhenIntervalsAreEqual() {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
        let provider = RefreshSpyProvider()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            elapsed: { 0 },
            boundarySleeper: { _ in throw CancellationError() }
        )

        XCTAssertFalse(viewModel.fastRefreshMatchesSlowInterval(for: RefreshSpyProvider.providerId))

        AutoRefreshPreferences.slowInterval = 60
        AutoRefreshPreferences.fastInterval = 60

        XCTAssertTrue(viewModel.fastRefreshMatchesSlowInterval(for: RefreshSpyProvider.providerId))
        XCTAssertEqual(viewModel.effectiveFastInterval(for: RefreshSpyProvider.providerId), 60)
    }

    func testElapsedTimeAcrossSleepExpiresTheWindowWithoutABurst() async {
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

        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)

        let fetchesBeforeWake = provider.fetchCallCount
        clock.advance(by: 10 * 60)
        viewModel.syncFastRefreshStatuses()

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
        XCTAssertEqual(provider.fetchCallCount, fetchesBeforeWake)
    }

    private func activity(usage: Double) -> ProviderActivityObservation {
        ProviderActivityObservation(metrics: [
            ProviderActivityMetric(id: "usage", kind: .usage, value: .number(Decimal(usage))),
        ])
    }
}
