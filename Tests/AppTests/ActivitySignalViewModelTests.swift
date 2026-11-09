@testable import App
import Core
import Foundation
import XCTest

private struct ActivitySignalTestFailure: Error {}

@MainActor
final class ActivitySignalViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.activity-signal-view-model"
    private let providerId = ActivitySignalSpyProvider.providerId
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(defaults)
        AutoRefreshPreferences.setUserDefaults(defaults)
        AutoRefreshPreferences.setEnabled(true, for: providerId)
        AutoRefreshPreferences.mode = .smart
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(.standard)
        AutoRefreshPreferences.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testSignalOnTheFirstBaselineEntersFastModeAndPullsTheRequestForward() async {
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)
        let baselineIntervals = await recorder.intervals()
        XCTAssertEqual(baselineIntervals, [AutoRefreshPreferences.slowInterval])
        XCTAssertEqual(viewModel.smartRefreshCadence(for: providerId), .slow)

        provider.send()
        await waitForIntervals(on: recorder, count: 2)

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, AutoRefreshPreferences.fastInterval)
        XCTAssertEqual(viewModel.smartRefreshCadence(for: providerId), .fast)
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: providerId))
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testRegularModeKeepsTheSubscriptionButDiscardsSignals() async {
        AutoRefreshPreferences.mode = .regular
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)
        XCTAssertEqual(provider.activeSubscriptionCount, 1)

        provider.send()
        await yieldSeveralTimes()

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals, [AutoRefreshPreferences.slowInterval])
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: providerId))
    }

    func testSignalsAreDiscardedWhenAutomaticRefreshIsOff() async {
        AutoRefreshPreferences.setEnabled(false, for: providerId)
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitUntil { provider.fetchCallCount >= 1 }
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        await waitUntil { provider.activeSubscriptionCount == 1 }
        XCTAssertEqual(provider.activeSubscriptionCount, 1)

        provider.send()
        await yieldSeveralTimes()

        let intervals = await recorder.intervals()
        XCTAssertTrue(intervals.isEmpty)
        XCTAssertEqual(viewModel.smartRefreshCadence(for: providerId), .slow)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: providerId))
    }

    func testAnEarlierDeadlineStaysAsItIs() async {
        let clock = TestElapsedClock()
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder, clock: clock)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)
        provider.send()
        await waitForIntervals(on: recorder, count: 2)
        let deadline = viewModel.refreshLoops[providerId]?.deadline
        XCTAssertEqual(deadline, AutoRefreshPreferences.fastInterval)

        clock.advance(by: 10)
        provider.send()
        await yieldSeveralTimes()

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(viewModel.refreshLoops[providerId]?.deadline, deadline)
    }

    func testABurstOfSignalsLeavesOnePendingRequest() async {
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)

        for _ in 0 ..< 5 {
            provider.send()
        }
        await waitForIntervals(on: recorder, count: 2)
        await yieldSeveralTimes()

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals, [AutoRefreshPreferences.slowInterval, AutoRefreshPreferences.fastInterval])
        XCTAssertNotNil(viewModel.refreshLoops[providerId])
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testAnInFlightRequestAbsorbsTheSignal() async {
        let gate = ControlledSleeper()
        let provider = ActivitySignalSpyProvider()
        provider.fetchGate = gate
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitForPendingSleeps(on: gate, count: 1)
        await waitUntil { provider.activeSubscriptionCount == 1 }

        provider.send()
        await waitUntil { viewModel.isFastAutomaticRefreshActive(for: self.providerId) }
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: providerId))
        XCTAssertNil(viewModel.refreshLoops[providerId])
        let intervalsWhileInFlight = await recorder.intervals()
        XCTAssertTrue(intervalsWhileInFlight.isEmpty)

        await gate.releaseNext()
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        await waitForIntervals(on: recorder, count: 1)

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals, [AutoRefreshPreferences.fastInterval])
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testTheFailureHoldStillAppliesAfterASignal() async {
        let provider = ActivitySignalSpyProvider()
        provider.errorToThrow = ActivitySignalTestFailure()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)
        XCTAssertTrue(viewModel.isWithinFailureHold(providerId))

        provider.send()
        await waitUntil { viewModel.isFastAutomaticRefreshActive(for: self.providerId) }
        await yieldSeveralTimes()

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals, [AutoRefreshPreferences.slowInterval])
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testTheProviderRetryGateStillAppliesAfterASignal() async {
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)
        let gate = ProviderRetryGate(now: { 0 })
        gate.record(retryAfter: 20 * 60)
        provider.retryGate = gate

        provider.send()
        await waitUntil { viewModel.isFastAutomaticRefreshActive(for: self.providerId) }
        await yieldSeveralTimes()

        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals, [AutoRefreshPreferences.slowInterval])
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testTheInferenceLockoutDiscardsSignals() async {
        let clock = TestElapsedClock()
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder, clock: clock)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)
        provider.send()
        await waitForIntervals(on: recorder, count: 2)
        XCTAssertTrue(viewModel.isFastAutomaticRefreshActive(for: providerId))

        clock.advance(by: SmartRefreshPolicy.inferenceEpisodeCap)
        viewModel.syncFastRefreshStatuses()
        XCTAssertEqual(viewModel.smartRefreshCadence(for: providerId), .slow)
        let intervalCount = await recorder.intervals().count

        provider.send()
        await yieldSeveralTimes()

        XCTAssertEqual(viewModel.smartRefreshCadence(for: providerId), .slow)
        XCTAssertFalse(viewModel.isFastAutomaticRefreshActive(for: providerId))
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.count, intervalCount)
    }

    func testDisablingCancelsTheSubscriptionAndReenablingSubscribesOnce() async {
        let provider = ActivitySignalSpyProvider()
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitForBaseline(on: viewModel, provider: provider, recorder: recorder)
        XCTAssertEqual(provider.activeSubscriptionCount, 1)

        viewModel.setProviderEnabled(false, for: providerId)
        await waitUntil { provider.activeSubscriptionCount == 0 }
        XCTAssertEqual(provider.activeSubscriptionCount, 0)

        viewModel.setProviderEnabled(true, for: providerId)
        await waitUntil { provider.fetchCallCount >= 2 }
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        await waitUntil { provider.activeSubscriptionCount == 1 }
        await yieldSeveralTimes()

        XCTAssertEqual(provider.activeSubscriptionCount, 1)
        XCTAssertEqual(provider.subscriptionCallCount, 2)
    }

    func testAProviderInSetupIsNeverSubscribed() async {
        let provider = ActivitySignalSpyProvider()
        provider.setupState = .setup(DisplayText(verbatim: "Install the client"))
        let recorder = IntervalRecorder()
        let viewModel = makeViewModel(provider: provider, recorder: recorder)
        await waitUntil { viewModel.setupTasks[self.providerId] == nil }
        await yieldSeveralTimes()

        XCTAssertEqual(provider.subscriptionCallCount, 0)
        XCTAssertEqual(provider.fetchCallCount, 0)
    }

    private func makeViewModel(
        provider: ActivitySignalSpyProvider,
        recorder: IntervalRecorder,
        clock: TestElapsedClock = TestElapsedClock()
    ) -> QuotaViewModel {
        ProviderEnablement.setEnabled(true, for: providerId)
        let registry = ProviderRegistry()
        registry.register(provider)
        return QuotaViewModel(
            registry: registry,
            errorLog: AppTestErrorLog.make(),
            autoRefreshSleeper: { interval in
                await recorder.record(interval)
                throw CancellationError()
            },
            smartRefreshBoundarySleeper: { _ in throw CancellationError() },
            smartRefreshElapsed: { clock.elapsed() },
            networkPath: TestNetworkPath(),
            wakeNetworkSleeper: { _ in throw CancellationError() },
            retryGateExpirySleeper: { _ in throw CancellationError() }
        )
    }

    private func waitForBaseline(
        on viewModel: QuotaViewModel,
        provider: ActivitySignalSpyProvider,
        recorder: IntervalRecorder
    ) async {
        await waitUntil { provider.fetchCallCount >= 1 }
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        await waitUntil { provider.activeSubscriptionCount == 1 }
        await waitForIntervals(on: recorder, count: 1)
    }
}

private final class ActivitySignalSpyProvider: AIProvider, ActivitySignaling, @unchecked Sendable {
    static let providerId = "activity-signal-spy"
    static let providerName = "Activity Signal Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let refreshCharacteristics = ProviderRefreshCharacteristics(canInvokeInference: true)

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Date>.Continuation] = [:]
    private var subscriptions = 0

    var fetchCallCount = 0
    var fetchGate: ControlledSleeper?
    var errorToThrow: (any Error)?
    var setupState: ProviderState?
    var retryGate: ProviderRetryGate?

    var activeSubscriptionCount: Int {
        lock.withLock { continuations.count }
    }

    var subscriptionCallCount: Int {
        lock.withLock { subscriptions }
    }

    func isConfigured() -> Bool {
        true
    }

    func currentSetupState() async -> ProviderState? {
        setupState
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        if let fetchGate {
            try await fetchGate.sleep(0)
        }
        if let errorToThrow {
            throw errorToThrow
        }
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: DisplayText(verbatim: "10%"),
            lines: [UsageLine(label: DisplayText(verbatim: "Usage"), percentage: 10)],
            lastUpdated: Date(),
            activityObservation: ProviderActivityObservation(metrics: [
                ProviderActivityMetric(id: "usage", kind: .usage, value: .number(10)),
            ])
        )
    }

    func activitySignals() -> AsyncStream<Date> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Date>.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            lock.withLock { _ = self.continuations.removeValue(forKey: id) }
        }
        lock.withLock {
            continuations[id] = continuation
            subscriptions += 1
        }
        return stream
    }

    func activitySignalStatus() async -> ActivitySignalStatus {
        .active
    }

    func installActivitySignal() async throws {}

    func removeActivitySignal() async throws {}

    func send() {
        let active = lock.withLock { Array(continuations.values) }
        for continuation in active {
            continuation.yield(Date())
        }
    }
}
