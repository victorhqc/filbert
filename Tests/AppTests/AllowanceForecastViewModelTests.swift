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
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    let clock: ActivityTestClock
    let resetsAt: Date
    var consumed: Decimal = 20
    var isStale = false
    var windowDuration: TimeInterval?
    var fetchCallCount = 0

    init(clock: ActivityTestClock, resetsAt: Date) {
        self.clock = clock
        self.resetsAt = resetsAt
    }

    func isConfigured() -> Bool {
        true
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        return currentQuota()
    }

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
            headlineUsageLineId: "window"
        )
    }
}

@MainActor
final class AllowanceForecastViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.allowance-forecast"
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
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

    func testGenericProviderObtainsAForecastFromAcceptedResultsWithoutExtraFetches() async throws {
        let harness = makeHarness()
        await drive(harness, trace: [(0, 20), (5, 23), (10, 25), (15, 28), (20, 30)])

        let presentation = try presentation(harness, at: minute(20))
        _ = try self.presentation(harness, at: minute(25))

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.value, "30%")
        XCTAssertEqual(headline.status, "About \(CoarseDurationFormatting.string(from: 140 * 60)) of use remaining")
        XCTAssertEqual(harness.provider.fetchCallCount, 5)
    }

    func testATimelineTickBeforeTheLatestSampleUsesTheCurrentTime() async throws {
        let harness = makeHarness()
        await drive(harness, trace: [(0, 20), (5, 23), (10, 25), (15, 28), (20, 30)])

        let presentation = try presentation(harness, at: minute(18))

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.status, "About \(CoarseDurationFormatting.string(from: 140 * 60)) of use remaining")
    }

    func testForecastsLeaveBudgetPaceAndCompactStatusUnchanged() async throws {
        let harness = makeHarness(resetsAt: minute(3 * 24 * 60))
        harness.provider.windowDuration = UsageWindowDuration.week
        await drive(harness, trace: [(0, 20), (5, 23), (10, 25), (15, 28), (20, 30)])

        let shown = try loadedQuota(harness)
        let presentation = try presentation(harness, at: minute(20))
        let reported = harness.provider.currentQuota()

        XCTAssertNotNil(presentation.headline)
        XCTAssertEqual(shown.headline, reported.headline)
        let pace = try XCTUnwrap(BudgetPace(line: shown.lines[0], now: minute(20)))
        XCTAssertEqual(pace, BudgetPace(line: reported.lines[0], now: minute(20)))
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: shown, at: minute(20)), pace.tier)
    }

    func testSleepPausesTheForecastUntilANewBaseline() async throws {
        let harness = makeHarness()
        await drive(harness, trace: [(0, 20), (5, 23), (10, 25), (15, 28), (20, 30)])

        harness.viewModel.handleActivityWillSleep()

        let presentation = try presentation(harness, at: minute(21))
        XCTAssertNil(presentation.headline)
        XCTAssertEqual(presentation.rowLines["window"]?.text, "Forecast paused until fresh data arrives")
    }

    func testStaleQuotaPausesTheForecast() async throws {
        let harness = makeHarness()
        await drive(harness, trace: [(0, 20), (5, 23), (10, 25), (15, 28), (20, 30)])

        harness.clock.date = minute(22)
        harness.provider.consumed = 31
        harness.provider.isStale = true
        harness.viewModel.manualRefresh(for: ForecastSpyProvider.providerId)
        await waitForFetch(harness, count: 6)

        let presentation = try presentation(harness, at: minute(22))
        XCTAssertNil(presentation.headline)
        XCTAssertEqual(presentation.rowLines["window"]?.text, "Forecast paused until fresh data arrives")
    }

    func testDisablingTheProviderClearsItsHistory() async {
        let harness = makeHarness()
        await drive(harness, trace: [(0, 20), (5, 23)])
        XCTAssertTrue(harness.viewModel.hasAllowanceForecasts(for: ForecastSpyProvider.providerId))

        harness.viewModel.setProviderEnabled(false, for: ForecastSpyProvider.providerId)

        XCTAssertFalse(harness.viewModel.hasAllowanceForecasts(for: ForecastSpyProvider.providerId))
    }
}

private struct ProviderNotLoaded: Error {}

private struct ForecastHarness {
    let viewModel: QuotaViewModel
    let provider: ForecastSpyProvider
    let clock: ActivityTestClock
}

private extension AllowanceForecastViewModelTests {
    func minute(_ value: Double) -> Date {
        origin.addingTimeInterval(value * 60)
    }

    func makeHarness(resetsAt: Date? = nil) -> ForecastHarness {
        let clock = ActivityTestClock(origin)
        let provider = ForecastSpyProvider(clock: clock, resetsAt: resetsAt ?? minute(5 * 60))
        ProviderEnablement.setEnabled(true, for: ForecastSpyProvider.providerId)
        AutoRefreshPreferences.setEnabled(false, for: ForecastSpyProvider.providerId)
        let registry = ProviderRegistry()
        registry.register(provider)
        let viewModel = QuotaViewModel(
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
                harness.viewModel.manualRefresh(for: ForecastSpyProvider.providerId)
            }
            await waitForFetch(harness, count: index + 1)
        }
    }

    func waitForFetch(_ harness: ForecastHarness, count: Int) async {
        let providerId = ForecastSpyProvider.providerId
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
        guard case let .loaded(quota) = harness.viewModel.providerStates[ForecastSpyProvider.providerId] else {
            throw ProviderNotLoaded()
        }
        return quota
    }

    func presentation(_ harness: ForecastHarness, at date: Date) throws -> AllowanceForecastPresentation {
        try harness.viewModel.allowanceForecastPresentation(
            for: loadedQuota(harness),
            providerId: ForecastSpyProvider.providerId,
            at: date
        )
    }
}
