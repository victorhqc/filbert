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

    func isConfigured() -> Bool {
        true
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
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

@MainActor
func makeAutoRefreshViewModel(
    provider: RefreshSpyProvider,
    sleeper: @escaping @Sendable (TimeInterval) async throws -> Void,
    elapsed: @escaping @Sendable () -> TimeInterval = { 0 },
    boundarySleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
        throw CancellationError()
    }
) -> QuotaViewModel {
    ProviderEnablement.setEnabled(true, for: RefreshSpyProvider.providerId)
    let registry = ProviderRegistry()
    registry.register(provider)
    return QuotaViewModel(
        registry: registry,
        errorLog: AppTestErrorLog.make(),
        autoRefreshSleeper: sleeper,
        smartRefreshBoundarySleeper: boundarySleeper,
        smartRefreshElapsed: elapsed
    )
}

@MainActor
func waitForFetches(on provider: RefreshSpyProvider, count: Int) async {
    for _ in 0 ..< 100 where provider.fetchCallCount < count {
        await Task.yield()
    }
    XCTAssertGreaterThanOrEqual(provider.fetchCallCount, count)
}

@MainActor
func waitForFetchCompletion(on viewModel: QuotaViewModel, providerId: String) async {
    for _ in 0 ..< 100 where viewModel.fetchTasks[providerId] != nil {
        await Task.yield()
    }
    XCTAssertNil(viewModel.fetchTasks[providerId])
}

func waitForIntervals(on recorder: IntervalRecorder, count: Int) async {
    for _ in 0 ..< 100 where await recorder.intervals().count < count {
        await Task.yield()
    }
    let intervals = await recorder.intervals()
    XCTAssertGreaterThanOrEqual(intervals.count, count)
}

func yieldSeveralTimes() async {
    for _ in 0 ..< 10 {
        await Task.yield()
    }
}
