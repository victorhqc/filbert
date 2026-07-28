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
        let viewModel = makeViewModel(provider: provider) { interval in
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
        let viewModel = makeViewModel(provider: provider) { interval in
            await recorder.record(interval)
            throw CancellationError()
        }

        await waitForFetches(on: provider, count: 1)
        viewModel.setAutoRefreshEnabled(true, for: RefreshSpyProvider.providerId)
        await waitForIntervals(on: recorder, count: 1)

        viewModel.setAutoRefreshSlowInterval(15 * 60)
        await waitForIntervals(on: recorder, count: 2)

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals, [5 * 60, 15 * 60])
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testManualSmartRefreshCanEnterFastMode() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        let provider = RefreshSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider) { interval in
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

        XCTAssertEqual(viewModel.smartRefreshPolicy.cadence(for: RefreshSpyProvider.providerId), .fast)
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, 30)
    }

    func testScheduledRefreshUsesProactiveCapabilityBeforeQuotaFetch() async {
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        let provider = RefreshSpyProvider()
        let sleeper = FirstWakeSleeper()
        let viewModel = makeViewModel(provider: provider) { interval in
            try await sleeper.sleep(interval)
        }

        await waitForFetches(on: provider, count: 2)

        XCTAssertEqual(provider.proactiveRefreshCallCount, 1)
        let intervals = await sleeper.intervals()
        XCTAssertEqual(intervals.first, 5 * 60)
        XCTAssertTrue(viewModel.isAutoRefreshEnabled(for: RefreshSpyProvider.providerId))
    }

    private func makeViewModel(
        provider: RefreshSpyProvider,
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void
    ) -> QuotaViewModel {
        ProviderEnablement.setEnabled(true, for: RefreshSpyProvider.providerId)
        let registry = ProviderRegistry()
        registry.register(provider)
        return QuotaViewModel(registry: registry, autoRefreshSleeper: sleeper)
    }

    private func waitForFetches(on provider: RefreshSpyProvider, count: Int) async {
        for _ in 0 ..< 100 where provider.fetchCallCount < count {
            await Task.yield()
        }
        XCTAssertGreaterThanOrEqual(provider.fetchCallCount, count)
    }

    private func waitForIntervals(on recorder: IntervalRecorder, count: Int) async {
        for _ in 0 ..< 100 where await recorder.intervals().count < count {
            await Task.yield()
        }
        let intervals = await recorder.intervals()
        XCTAssertGreaterThanOrEqual(intervals.count, count)
    }

    private func yieldSeveralTimes() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }
}

private actor IntervalRecorder {
    private var values: [TimeInterval] = []

    func record(_ interval: TimeInterval) {
        values.append(interval)
    }

    func intervals() -> [TimeInterval] {
        values
    }
}

private actor FirstWakeSleeper {
    private var values: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) throws {
        values.append(interval)
        if values.count > 1 {
            throw CancellationError()
        }
    }

    func intervals() -> [TimeInterval] {
        values
    }
}

private final class RefreshSpyProvider: AIProvider, ProactiveRefreshable, @unchecked Sendable {
    static let providerId = "auto-refresh-spy"
    static let providerName = "Auto Refresh Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    var percentage = 10.0
    var fetchCallCount = 0
    var proactiveRefreshCallCount = 0

    func isConfigured() -> Bool {
        true
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "\(percentage)%",
            lines: [UsageLine(label: "Usage", percentage: percentage)],
            lastUpdated: Date()
        )
    }

    func proactiveRefresh() async throws {
        proactiveRefreshCallCount += 1
    }
}
