@testable import App
import Core
import Foundation
import XCTest

private struct SmartRefreshTestFailure: Error {}

@MainActor
final class AutoRefreshSmartSafetyTests: XCTestCase {
    private let suiteName = "filbert.tests.auto-refresh-smart-safety"
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

    func testManualRefreshWithoutASemanticChangeStartsTheActivityWindow() async {
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
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)

        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
    }

    func testRenewingFastStatusDoesNotReawardTheMenuBarBoost() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
        let clock = TestElapsedClock()
        let provider = RefreshSpyProvider()
        let activityDate = Date(timeIntervalSinceReferenceDate: 10000)
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            elapsed: { clock.elapsed() },
            boundarySleeper: { _ in throw CancellationError() },
            activityNow: { activityDate }
        )

        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        let afterEntry = viewModel.activityRuntime.policy.effectiveScore(
            for: RefreshSpyProvider.providerId,
            at: activityDate
        )
        XCTAssertEqual(afterEntry, MenuBarProviderActivityPolicy.fastEntryAward)

        viewModel.startSmartExtension(for: RefreshSpyProvider.providerId, duration: 15 * 60)
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
        XCTAssertEqual(
            viewModel.activityRuntime.policy.effectiveScore(
                for: RefreshSpyProvider.providerId,
                at: activityDate
            ),
            afterEntry
        )
    }

    func testManualRefreshHintIsIgnoredWhenAutomaticRefreshIsOff() async {
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

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
    }

    func testKeepCheckingExtensionUsesFastCadenceUntilItExpires() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
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

        viewModel.startSmartExtension(for: RefreshSpyProvider.providerId, duration: 15 * 60)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)
        XCTAssertEqual(viewModel.smartExtensionRemaining(for: RefreshSpyProvider.providerId), 15 * 60)
        await waitForIntervals(on: recorder, count: 2)
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, 30)

        clock.advance(by: 15 * 60)
        viewModel.syncFastRefreshStatuses()

        XCTAssertNil(viewModel.smartExtensionRemaining(for: RefreshSpyProvider.providerId))
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
    }

    func testStopExtensionResumesTheAutomaticPolicy() async {
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
        viewModel.startSmartExtension(for: RefreshSpyProvider.providerId, duration: 15 * 60)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)

        viewModel.stopSmartExtension(for: RefreshSpyProvider.providerId)

        XCTAssertNil(viewModel.smartExtensionRemaining(for: RefreshSpyProvider.providerId))
        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
    }

    func testFailureSchedulesTheSlowInterval() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
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

        provider.errorToThrow = SmartRefreshTestFailure()
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
        await waitForIntervals(on: recorder, count: 2)
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, 5 * 60)
    }

    func testProviderMinimumIntervalClampsTheFastCadence() async {
        AutoRefreshPreferences.setEnabled(true, for: ThrottledRefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
        ProviderEnablement.setEnabled(true, for: ThrottledRefreshSpyProvider.providerId)

        let clock = TestElapsedClock()
        let provider = ThrottledRefreshSpyProvider()
        let recorder = IntervalRecorder()
        let registry = ProviderRegistry()
        registry.register(provider)
        let viewModel = QuotaViewModel(
            registry: registry,
            errorLog: AppTestErrorLog.make(),
            autoRefreshSleeper: { interval in
                await recorder.record(interval)
                throw CancellationError()
            },
            smartRefreshBoundarySleeper: { _ in throw CancellationError() },
            smartRefreshElapsed: { clock.elapsed() }
        )

        await waitForThrottledFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: ThrottledRefreshSpyProvider.providerId)

        provider.percentage = 20
        viewModel.manualRefresh(for: ThrottledRefreshSpyProvider.providerId)
        await waitForThrottledFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: ThrottledRefreshSpyProvider.providerId)

        XCTAssertEqual(viewModel.smartRefreshCadence(for: ThrottledRefreshSpyProvider.providerId), .fast)
        await waitForIntervals(on: recorder, count: 2)
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, 120)
    }
}

@MainActor
private func waitForThrottledFetches(on provider: ThrottledRefreshSpyProvider, count: Int) async {
    for _ in 0 ..< 100 where provider.fetchCallCount < count {
        await Task.yield()
    }
    XCTAssertGreaterThanOrEqual(provider.fetchCallCount, count)
}
