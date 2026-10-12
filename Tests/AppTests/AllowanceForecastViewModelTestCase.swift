@testable import App
import Core
import Foundation
import XCTest

/// Uses only the generic contract: no Core or App code knows this provider.
final class ForecastSpyProvider: AIProvider, @unchecked Sendable {
    static let providerId = "forecast-spy"
    static let providerName = "Forecast Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!

    let clock: ActivityTestClock
    let resetsAt: Date
    var consumed: Decimal = 20
    var isStale = false
    var windowDuration: TimeInterval?
    var headlineUsageLineId: String? = "window"
    var fetchError: (any Error)?
    var fetchCallCount = 0

    init(clock: ActivityTestClock, resetsAt: Date) {
        self.clock = clock
        self.resetsAt = resetsAt
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        if let fetchError {
            throw fetchError
        }
        return currentQuota()
    }

    func importCredentials() async throws {}

    func currentQuota() -> ProviderQuota {
        let percentage = NSDecimalNumber(decimal: consumed).doubleValue
        let line = UsageLine(
            label: "Window",
            percentage: percentage,
            resetDate: resetsAt,
            windowDuration: windowDuration,
            id: "window",
            limitGroup: "spy"
        )
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "\(Int(percentage))% · resets soon",
            lines: [line],
            lastUpdated: clock.date,
            isStale: isStale,
            activityObservation: ProviderActivityObservation(
                metrics: [
                    ProviderActivityMetric(
                        id: "window",
                        kind: .usage,
                        value: .number(consumed),
                        forecastDescriptor: AllowanceForecastDescriptor(
                            accounting: .fixedPeriod(limit: 100, resetsAt: resetsAt),
                            unit: .percentagePoints,
                            resolution: 1,
                            timing: .source(clock.date),
                            usageLineId: "window"
                        )
                    ),
                ],
                freshness: .fresh
            ),
            headlineUsageLineId: headlineUsageLineId
        )
    }
}

struct ForecastSpyFailure: Error {}

struct ForecastHarness {
    let viewModel: QuotaViewModel
    let provider: ForecastSpyProvider
    let clock: ActivityTestClock
}

@MainActor
class AllowanceForecastViewModelTestCase: XCTestCase {
    let providerId = ForecastSpyProvider.providerId
    /// 10 points in 20 minutes with 70 remaining: 140 minutes of use.
    let steadyTrace: [(minute: Double, consumed: Decimal)] = [(0, 20), (5, 23), (10, 25), (15, 28), (20, 30)]
    private let suiteName = "filbert.tests.allowance-forecast"
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(defaults)
        AutoRefreshPreferences.setUserDefaults(defaults)
        ProviderOverrides.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(.standard)
        AutoRefreshPreferences.setUserDefaults(.standard)
        ProviderOverrides.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func minute(_ value: Double) -> Date {
        origin.addingTimeInterval(value * 60)
    }

    func makeHarness(resetsAt: Date? = nil) throws -> ForecastHarness {
        let clock = ActivityTestClock(origin)
        let provider = ForecastSpyProvider(clock: clock, resetsAt: resetsAt ?? minute(5 * 60))
        ProviderEnablement.setEnabled(true, for: providerId)
        AutoRefreshPreferences.setEnabled(false, for: providerId)
        let keychain = Keychain(storage: ViewModelKeychainStorage(), service: "allowance-forecast")
        try keychain.save("forecast-key", for: providerId)
        let registry = ProviderRegistry(keychain: keychain)
        registry.register(provider)
        let viewModel = QuotaViewModel(
            keychain: keychain,
            registry: registry,
            errorLog: AppTestErrorLog.make(),
            autoRefreshSleeper: { _ in throw CancellationError() },
            smartRefreshBoundarySleeper: { _ in throw CancellationError() },
            activityNow: { clock.date }
        )
        return ForecastHarness(viewModel: viewModel, provider: provider, clock: clock)
    }

    func drive(_ harness: ForecastHarness, trace: [(minute: Double, consumed: Decimal)]) async {
        for (index, point) in trace.enumerated() {
            harness.clock.date = minute(point.minute)
            harness.provider.consumed = point.consumed
            if index > 0 {
                harness.viewModel.manualRefresh(for: providerId)
            }
            await waitForFetch(harness, count: index + 1)
        }
    }

    func waitForFetch(_ harness: ForecastHarness, count: Int) async {
        func isPending() -> Bool {
            harness.provider.fetchCallCount < count || harness.viewModel.fetchTasks[providerId] != nil
        }
        for _ in 0 ..< 1000 where isPending() {
            await Task.yield()
        }
        XCTAssertEqual(harness.provider.fetchCallCount, count)
        XCTAssertNil(harness.viewModel.fetchTasks[providerId])
    }

    func loadedQuota(_ harness: ForecastHarness) throws -> ProviderQuota {
        guard case let .loaded(quota) = harness.viewModel.providerStates[providerId] else {
            throw ProviderNotLoaded()
        }
        return quota
    }

    func presentation(_ harness: ForecastHarness, at date: Date) throws -> AllowanceForecastPresentation {
        try harness.viewModel.allowanceForecastPresentation(
            for: loadedQuota(harness),
            providerId: providerId,
            at: date
        )
    }
}

private struct ProviderNotLoaded: Error {}
