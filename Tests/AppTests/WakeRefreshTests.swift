@testable import App
import Core
import Foundation
import XCTest

private struct WakeTestFailure: Error {}

@MainActor
final class WakeRefreshTests: XCTestCase {
    private let suiteName = "filbert.tests.wake-refresh"
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

    func testWakeRefreshesAFailedProviderOnceWhenTheNetworkReturns() async throws {
        let provider = RefreshSpyProvider()
        let networkPath = TestNetworkPath()
        let wakeSleeper = ControlledSleeper()
        let errorLog = AppTestErrorLog.make()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            errorLog: errorLog,
            networkPath: networkPath,
            wakeNetworkSleeper: { try await wakeSleeper.sleep($0) }
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        provider.errorToThrow = WakeTestFailure()
        viewModel.performFetch(for: providerId, origin: .automatic)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        XCTAssertTrue(viewModel.isWithinFailureHold(providerId))
        XCTAssertNotNil(viewModel.refreshErrors[providerId])

        networkPath.set(.unsatisfied)
        await yieldSeveralTimes()
        viewModel.handleWakeForRefresh()
        viewModel.performFetch(for: providerId, origin: .automatic)
        await waitForPendingSleeps(on: wakeSleeper, count: 1)
        await wakeSleeper.releaseNext()
        await waitForPendingSleeps(on: wakeSleeper, count: 1)
        let requested = await wakeSleeper.requestedIntervals()
        XCTAssertEqual(requested, [5, 25])
        XCTAssertEqual(provider.fetchCallCount, 2)

        provider.errorToThrow = nil
        networkPath.set(.satisfied)
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
        await yieldSeveralTimes()

        XCTAssertEqual(provider.fetchCallCount, 3)
        XCTAssertFalse(viewModel.isAwaitingNetworkAfterWake)
        XCTAssertFalse(viewModel.isWithinFailureHold(providerId))
        XCTAssertNil(viewModel.refreshErrors[providerId])
        XCTAssertTrue(viewModel.providersAwaitingNetwork.isEmpty)
        XCTAssertEqual(try logRecords(errorLog).count, 1)
    }

    func testWakeProceedsAfterTheSettleDelayWhenTheNetworkIsUp() async {
        let provider = RefreshSpyProvider()
        let wakeSleeper = ControlledSleeper()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            wakeNetworkSleeper: { try await wakeSleeper.sleep($0) }
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        provider.errorToThrow = WakeTestFailure()
        viewModel.performFetch(for: providerId, origin: .automatic)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        provider.errorToThrow = nil
        viewModel.handleWakeForRefresh()
        await waitForPendingSleeps(on: wakeSleeper, count: 1)
        await wakeSleeper.releaseNext()
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        let requested = await wakeSleeper.requestedIntervals()
        XCTAssertEqual(requested, [5])
        XCTAssertNil(viewModel.refreshErrors[providerId])
    }

    func testWakeCapEndsTheWaitButOfflineRequestsStillDefer() async {
        let provider = RefreshSpyProvider()
        let networkPath = TestNetworkPath()
        let wakeSleeper = ControlledSleeper()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            networkPath: networkPath,
            wakeNetworkSleeper: { try await wakeSleeper.sleep($0) }
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        networkPath.set(.unsatisfied)
        await yieldSeveralTimes()
        viewModel.handleWakeForRefresh()
        viewModel.performFetch(for: providerId, origin: .automatic)
        await waitForPendingSleeps(on: wakeSleeper, count: 1)
        await wakeSleeper.releaseNext()
        await waitForPendingSleeps(on: wakeSleeper, count: 1)
        await wakeSleeper.releaseNext()
        await waitUntil { !viewModel.isAwaitingNetworkAfterWake }

        XCTAssertFalse(viewModel.isAwaitingNetworkAfterWake)
        XCTAssertEqual(provider.fetchCallCount, 1)
        XCTAssertTrue(viewModel.providersAwaitingNetwork.contains(providerId))

        networkPath.set(.satisfied)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)
    }

    func testWakeLeavesAHealthyProviderThatIsNotDueAlone() async {
        let provider = RefreshSpyProvider()
        let wakeSleeper = ControlledSleeper()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            wakeNetworkSleeper: { try await wakeSleeper.sleep($0) }
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        viewModel.handleWakeForRefresh()
        await waitForPendingSleeps(on: wakeSleeper, count: 1)
        await wakeSleeper.releaseNext()
        await waitUntil { !viewModel.isAwaitingNetworkAfterWake }
        await yieldSeveralTimes()

        XCTAssertFalse(viewModel.isAwaitingNetworkAfterWake)
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testWakeLogsItsTrigger() async throws {
        let provider = RefreshSpyProvider()
        let wakeSleeper = ControlledSleeper()
        let errorLog = AppTestErrorLog.make()
        let viewModel = makeAutoRefreshViewModel(
            provider: provider,
            sleeper: { _ in throw CancellationError() },
            errorLog: errorLog,
            wakeNetworkSleeper: { try await wakeSleeper.sleep($0) }
        )
        await waitForFetches(on: provider, count: 1)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        provider.errorToThrow = WakeTestFailure()
        viewModel.manualRefresh(for: providerId)
        await waitForFetches(on: provider, count: 2)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        viewModel.handleWakeForRefresh()
        await waitForPendingSleeps(on: wakeSleeper, count: 1)
        await wakeSleeper.releaseNext()
        await waitForFetches(on: provider, count: 3)
        await waitForFetchCompletion(on: viewModel, providerId: providerId)

        let triggers = try logRecords(errorLog).map { $0["trigger"] as? String }
        XCTAssertEqual(triggers, ["manual", "wake"])
    }

    private func logRecords(_ errorLog: ErrorLog) throws -> [[String: Any]] {
        let data = try Data(contentsOf: errorLog.fileURL)
        return try data.split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }
}
