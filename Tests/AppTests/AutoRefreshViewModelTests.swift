@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class AutoRefreshViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.auto-refresh-view-model"
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

    func testInitialLoadDoesNotScheduleWhenAutomaticRefreshIsOff() async {
        let provider = RefreshSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeAutoRefreshViewModel(provider: provider) { interval in
            await recorder.record(interval)
            throw CancellationError()
        }

        await waitForFetches(on: provider, count: 1)
        await yieldSeveralTimes()

        let intervals = await recorder.intervals()
        XCTAssertTrue(intervals.isEmpty)
        XCTAssertFalse(viewModel.isAutoRefreshEnabled(for: RefreshSpyProvider.providerId))
    }

    func testIntervalChangeReschedulesEligibleProviderWithoutFetchingAgain() async {
        let provider = RefreshSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeAutoRefreshViewModel(provider: provider) { interval in
            await recorder.record(interval)
            throw CancellationError()
        }

        await waitForFetches(on: provider, count: 1)
        viewModel.setAutoRefreshEnabled(true, for: RefreshSpyProvider.providerId)
        await waitForIntervals(on: recorder, count: 1)

        viewModel.setAutoRefreshSlowInterval(17 * 60)
        await waitForIntervals(on: recorder, count: 2)

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals, [5 * 60, 17 * 60])
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testManualSmartRefreshCanEnterFastMode() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        let provider = RefreshSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeAutoRefreshViewModel(provider: provider) { interval in
            await recorder.record(interval)
            throw CancellationError()
        }

        await waitForFetches(on: provider, count: 1)
        await waitForIntervals(on: recorder, count: 1)
        viewModel.setAutoRefreshMode(.smart)
        await waitForIntervals(on: recorder, count: 2)
        provider.percentage = 20

        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForIntervals(on: recorder, count: 3)

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .fast)
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, 30)
    }

    func testPresentationOnlySmartRefreshKeepsSlowSchedule() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        let provider = RefreshSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeAutoRefreshViewModel(provider: provider) { interval in
            await recorder.record(interval)
            throw CancellationError()
        }

        await waitForFetches(on: provider, count: 1)
        await waitForIntervals(on: recorder, count: 1)
        viewModel.setAutoRefreshMode(.smart)
        await waitForIntervals(on: recorder, count: 2)
        provider.presentationRevision += 1

        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForIntervals(on: recorder, count: 3)

        XCTAssertEqual(viewModel.smartRefreshCadence(for: RefreshSpyProvider.providerId), .slow)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, 5 * 60)
    }

    func testFastRefreshStatusIdentifiesOnlyTheActiveProvider() async {
        AutoRefreshPreferences.mode = .smart
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.setEnabled(true, for: SecondaryRefreshSpyProvider.providerId)
        ProviderEnablement.setEnabled(true, for: RefreshSpyProvider.providerId)
        ProviderEnablement.setEnabled(true, for: SecondaryRefreshSpyProvider.providerId)

        let activeProvider = RefreshSpyProvider()
        let inactiveProvider = SecondaryRefreshSpyProvider()
        let registry = ProviderRegistry()
        registry.register(activeProvider)
        registry.register(inactiveProvider)
        let viewModel = QuotaViewModel(registry: registry, errorLog: AppTestErrorLog.make()) { _ in
            throw CancellationError()
        }

        await waitForFetches(on: activeProvider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        activeProvider.percentage = 20
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: activeProvider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: SecondaryRefreshSpyProvider.providerId))
    }

    func testFastRefreshStatusClearsWhenModeOrEligibilityChanges() async {
        AutoRefreshPreferences.mode = .smart
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        let provider = RefreshSpyProvider()
        let viewModel = makeAutoRefreshViewModel(provider: provider) { _ in
            throw CancellationError()
        }

        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        provider.percentage = 20
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))

        viewModel.setAutoRefreshMode(.regular)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))

        viewModel.setAutoRefreshMode(.smart)
        provider.percentage = 30
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))

        viewModel.setAutoRefreshEnabled(false, for: RefreshSpyProvider.providerId)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))

        viewModel.setAutoRefreshEnabled(true, for: RefreshSpyProvider.providerId)
        provider.percentage = 40
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 4)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))

        viewModel.setProviderEnabled(false, for: RefreshSpyProvider.providerId)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: RefreshSpyProvider.providerId))
    }

    func testScheduledRefreshUsesProactiveCapabilityBeforeQuotaFetch() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        let provider = RefreshSpyProvider()
        let sleeper = FirstWakeSleeper()
        let viewModel = makeAutoRefreshViewModel(provider: provider) { interval in
            try await sleeper.sleep(interval)
        }

        await waitForFetches(on: provider, count: 2)

        XCTAssertEqual(provider.proactiveRefreshCallCount, 1)
        let intervals = await sleeper.intervals()
        XCTAssertEqual(intervals.first, 5 * 60)
        XCTAssertTrue(viewModel.isAutoRefreshEnabled(for: RefreshSpyProvider.providerId))
    }
}
