@testable import App
import Core
import Foundation
import XCTest

private struct RecoveryTestFailure: Error {}

@MainActor
final class RefreshRecoveryTests: XCTestCase {
    private let suiteName = "filbert.tests.refresh-recovery"
    private var defaults: UserDefaults!
    private let providerId = RefreshSpyProvider.providerId

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(defaults)
        AutoRefreshPreferences.setUserDefaults(defaults)
        AutoRefreshPreferences.setEnabled(true, for: RefreshSpyProvider.providerId)
        AutoRefreshPreferences.mode = .smart
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(.standard)
        AutoRefreshPreferences.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Failure hold

    func testManualRefreshReplacesTheFailureHold() async {
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

        provider.errorToThrow = RecoveryTestFailure()
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
        XCTAssertTrue(viewModel.isWithinFailureHold(RefreshSpyProvider.providerId))
        XCTAssertNotNil(viewModel.refreshErrors[RefreshSpyProvider.providerId])

        provider.errorToThrow = nil
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        XCTAssertEqual(provider.fetchCallCount, 3)
        XCTAssertFalse(viewModel.isWithinFailureHold(RefreshSpyProvider.providerId))
        XCTAssertNil(viewModel.refreshErrors[RefreshSpyProvider.providerId])
    }

    func testFailureHoldStillBlocksAutomaticRefresh() async {
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

        provider.errorToThrow = RecoveryTestFailure()
        viewModel.manualRefresh(for: RefreshSpyProvider.providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)

        viewModel.performFetch(for: RefreshSpyProvider.providerId, origin: .automatic)
        await yieldSeveralTimes()
        XCTAssertEqual(provider.fetchCallCount, 2)

        clock.advance(by: 5 * 60)
        viewModel.performFetch(for: RefreshSpyProvider.providerId, origin: .automatic)
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: RefreshSpyProvider.providerId)
    }

    // MARK: - Provider retry gate

    func testRetryGateDisablesManualRefreshUntilItExpires() async {
        let clock = TestElapsedClock()
        let provider = RefreshSpyProvider()
        provider.retryGate = ProviderRetryGate(now: { clock.elapsed() })
        let expirySleeper = ControlledSleeper()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            elapsed: { clock.elapsed() },
            retryGateExpirySleeper: { try await expirySleeper.sleep($0) }
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        XCTAssertNil(viewModel.manualRefreshWaitRemaining(for: providerId))

        provider.retryGate?.record(retryAfter: 120)
        viewModel.scheduleRetryGateExpiry(for: providerId)
        XCTAssertEqual(viewModel.manualRefreshWaitRemaining(for: providerId), 120)

        viewModel.manualRefresh(for: providerId)
        await yieldSeveralTimes()
        XCTAssertEqual(provider.fetchCallCount, 1)

        await waitForPendingSleeps(on: expirySleeper, count: 1)
        let requested = await expirySleeper.requestedIntervals()
        XCTAssertEqual(requested, [120])
        let revision = viewModel.retryGateRevision
        clock.advance(by: 120)
        await expirySleeper.releaseNext()
        await waitUntil { viewModel.retryGateRevision != revision }
        XCTAssertGreaterThan(viewModel.retryGateRevision, revision)
        XCTAssertNil(viewModel.manualRefreshWaitRemaining(for: providerId))

        viewModel.manualRefresh(for: providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
    }

    // MARK: - Offline deferral

    func testAutomaticRefreshWaitsForTheNetworkAndRunsOnce() async {
        let provider = RefreshSpyProvider()
        let networkPath = TestNetworkPath()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            networkPath: networkPath
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        networkPath.set(.unsatisfied)
        await yieldSeveralTimes()
        viewModel.performFetch(for: providerId, origin: .automatic)
        viewModel.performFetch(for: providerId, origin: .automatic)
        await yieldSeveralTimes()

        XCTAssertEqual(provider.fetchCallCount, 1)
        XCTAssertTrue(viewModel.providersAwaitingNetwork.contains(providerId))
        XCTAssertFalse(viewModel.isWithinFailureHold(providerId))
        XCTAssertNil(viewModel.refreshErrors[providerId])

        networkPath.set(.satisfied)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        await yieldSeveralTimes()
        XCTAssertEqual(provider.fetchCallCount, 2)
        XCTAssertTrue(viewModel.providersAwaitingNetwork.isEmpty)
    }

    func testDeferredRefreshStillWaitsForTheRetryGate() async {
        let clock = TestElapsedClock()
        let provider = RefreshSpyProvider()
        provider.retryGate = ProviderRetryGate(now: { clock.elapsed() })
        let networkPath = TestNetworkPath()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            elapsed: { clock.elapsed() },
            networkPath: networkPath
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        networkPath.set(.unsatisfied)
        await yieldSeveralTimes()
        viewModel.performFetch(for: providerId, origin: .automatic)
        provider.retryGate?.record(retryAfter: 300)
        networkPath.set(.satisfied)
        await yieldSeveralTimes()

        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testConnectivityFailureSetsNoHoldAndRetriesWhenTheNetworkReturns() async throws {
        let provider = RefreshSpyProvider()
        let networkPath = TestNetworkPath()
        let recorder = IntervalRecorder()
        let errorLog = AppTestErrorLog.make()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { interval in
                await recorder.record(interval)
                throw CancellationError()
            },
            errorLog: errorLog,
            networkPath: networkPath
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        provider.errorToThrow = URLError(.notConnectedToInternet)
        viewModel.performFetch(for: providerId, origin: .automatic)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        XCTAssertNotNil(viewModel.refreshErrors[providerId])
        guard case .loaded = viewModel.providerStates[providerId] else {
            return XCTFail("A connectivity failure must keep last-known data")
        }
        XCTAssertFalse(viewModel.isWithinFailureHold(providerId))
        XCTAssertTrue(viewModel.providersAwaitingNetwork.contains(providerId))
        let intervals = await recorder.intervals()
        XCTAssertEqual(intervals.last, 5 * 60)

        let record = try XCTUnwrap(logRecords(errorLog).last)
        XCTAssertEqual(record["operation"] as? String, "fetch-quota")
        XCTAssertEqual(record["trigger"] as? String, "automatic")
        XCTAssertEqual(record["networkPath"] as? String, "satisfied")
        XCTAssertEqual(record["errorDomain"] as? String, NSURLErrorDomain)
        XCTAssertEqual(record["errorCode"] as? Int, URLError.notConnectedToInternet.rawValue)

        provider.errorToThrow = nil
        networkPath.set(.unsatisfied)
        networkPath.set(.satisfied)
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        XCTAssertNil(viewModel.refreshErrors[providerId])
    }

    func testOrdinaryFailureStillSetsTheHold() async {
        let provider = RefreshSpyProvider()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() }
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        provider.errorToThrow = RecoveryTestFailure()
        viewModel.performFetch(for: providerId, origin: .automatic)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        XCTAssertTrue(viewModel.isWithinFailureHold(providerId))
        XCTAssertFalse(viewModel.providersAwaitingNetwork.contains(providerId))
    }

    private func logRecords(_ errorLog: ErrorLog) throws -> [[String: Any]] {
        let data = try Data(contentsOf: errorLog.fileURL)
        return try data.split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }
}
