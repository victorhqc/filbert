@testable import App
import Core
import Foundation
import XCTest

actor IntervalRecorder {
    private var values: [TimeInterval] = []

    func record(_ interval: TimeInterval) {
        values.append(interval)
    }

    func intervals() -> [TimeInterval] {
        values
    }
}

actor FirstWakeSleeper {
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

final class TestElapsedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0

    func elapsed() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        value += interval
    }
}

final class RefreshSpyProvider: AIProvider, ProactiveRefreshable, @unchecked Sendable {
    static let providerId = "auto-refresh-spy"
    static let providerName = "Auto Refresh Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    var percentage = 10.0
    var presentationRevision = 0
    var fetchCallCount = 0
    var proactiveRefreshCallCount = 0
    var errorToThrow: (any Error)?
    var retryGate: ProviderRetryGate?

    func isConfigured() -> Bool {
        true
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "\(percentage)% \(presentationRevision)",
            lines: [UsageLine(label: "Usage \(presentationRevision)", percentage: percentage)],
            lastUpdated: Date(),
            activityObservation: ProviderActivityObservation(metrics: [
                ProviderActivityMetric(
                    id: "usage",
                    kind: .usage,
                    value: .number(Decimal(percentage))
                ),
            ])
        )
    }

    func proactiveRefresh() async throws {
        proactiveRefreshCallCount += 1
    }
}

final class SecondaryRefreshSpyProvider: AIProvider, @unchecked Sendable {
    static let providerId = "secondary-auto-refresh-spy"
    static let providerName = "Secondary Auto Refresh Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    var fetchCallCount = 0

    func isConfigured() -> Bool {
        true
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "10%",
            lines: [UsageLine(label: "Usage", percentage: 10)],
            lastUpdated: Date(),
            activityObservation: ProviderActivityObservation(metrics: [
                ProviderActivityMetric(id: "usage", kind: .usage, value: .number(10)),
            ])
        )
    }
}

final class ThrottledRefreshSpyProvider: AIProvider, @unchecked Sendable {
    static let providerId = "throttled-auto-refresh-spy"
    static let providerName = "Throttled Auto Refresh Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let refreshCharacteristics = ProviderRefreshCharacteristics(
        minimumInterval: 120,
        canInvokeInference: true
    )

    var percentage = 10.0
    var fetchCallCount = 0

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
            lastUpdated: Date(),
            activityObservation: ProviderActivityObservation(metrics: [
                ProviderActivityMetric(id: "usage", kind: .usage, value: .number(Decimal(percentage))),
            ])
        )
    }
}

@MainActor
func makeAutoRefreshViewModel(
    provider: RefreshSpyProvider,
    sleeper: @escaping @Sendable (TimeInterval) async throws -> Void,
    elapsed: @escaping @Sendable () -> TimeInterval = { 0 },
    boundarySleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
        throw CancellationError()
    },
    activityNow: @escaping @Sendable () -> Date = { Date() },
    errorLog: ErrorLog = AppTestErrorLog.make(),
    networkPath: any NetworkPathObserving = TestNetworkPath(),
    wakeNetworkSleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
        throw CancellationError()
    },
    retryGateExpirySleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
        throw CancellationError()
    }
) -> QuotaViewModel {
    ProviderEnablement.setEnabled(true, for: RefreshSpyProvider.providerId)
    let registry = ProviderRegistry()
    registry.register(provider)
    return QuotaViewModel(
        registry: registry,
        errorLog: errorLog,
        autoRefreshSleeper: sleeper,
        smartRefreshBoundarySleeper: boundarySleeper,
        smartRefreshElapsed: elapsed,
        activityNow: activityNow,
        networkPath: networkPath,
        wakeNetworkSleeper: wakeNetworkSleeper,
        retryGateExpirySleeper: retryGateExpirySleeper
    )
}

final class TestNetworkPath: NetworkPathObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus: NetworkPathStatus
    private var continuation: AsyncStream<NetworkPathStatus>.Continuation?

    init(_ status: NetworkPathStatus = .satisfied) {
        currentStatus = status
    }

    var status: NetworkPathStatus {
        lock.withLock { currentStatus }
    }

    func statusChanges() -> AsyncStream<NetworkPathStatus> {
        let (stream, continuation) = AsyncStream<NetworkPathStatus>.makeStream()
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func set(_ status: NetworkPathStatus) {
        let continuation = lock.withLock {
            currentStatus = status
            return self.continuation
        }
        continuation?.yield(status)
    }
}

actor ControlledSleeper {
    private var waiters: [CheckedContinuation<Void, any Error>] = []
    private var requests: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) async throws {
        requests.append(interval)
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releaseNext() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func requestedIntervals() -> [TimeInterval] {
        requests
    }

    func pendingCount() -> Int {
        waiters.count
    }
}

@MainActor
func waitForPendingSleeps(on sleeper: ControlledSleeper, count: Int) async {
    await waitUntil { await sleeper.pendingCount() >= count }
    let pending = await sleeper.pendingCount()
    XCTAssertGreaterThanOrEqual(pending, count)
}

/// Bounded by time, not by a yield count, so a slow scheduler cannot end the
/// wait before the awaited work has had a chance to run.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while await !condition(), ContinuousClock.now < deadline {
        await Task.yield()
    }
}

@MainActor
func waitForFetches(on provider: RefreshSpyProvider, count: Int) async {
    await waitUntil { provider.fetchCallCount >= count }
    XCTAssertGreaterThanOrEqual(provider.fetchCallCount, count)
}

@MainActor
func waitForFetchCompletion(on viewModel: QuotaViewModel, providerId: String) async {
    await waitUntil { viewModel.fetchTasks[providerId] == nil }
    XCTAssertNil(viewModel.fetchTasks[providerId])
}

@MainActor
func waitForIntervals(on recorder: IntervalRecorder, count: Int) async {
    await waitUntil { await recorder.intervals().count >= count }
    let intervals = await recorder.intervals()
    XCTAssertGreaterThanOrEqual(intervals.count, count)
}

func yieldSeveralTimes() async {
    for _ in 0 ..< 10 {
        await Task.yield()
    }
}
