@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class MenuBarProviderSelectionViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.menu-bar-provider-selection-view-model"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        MenuBarProviderSelectionPreferences.setUserDefaults(defaults)
        VintageMacIcon.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        MenuBarProviderSelectionPreferences.setUserDefaults(.standard)
        VintageMacIcon.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testChangingSelectionModeUpdatesTheViewModelAndPersistedPreference() {
        let viewModel = QuotaViewModel(registry: ProviderRegistry())
        viewModel.configuredProviderIds = ["first", "newer"]
        viewModel.enabledProviderIds = ["first", "newer"]
        viewModel.providerStates = [
            "first": loadedState(for: "first", updatedAt: 1),
            "newer": loadedState(for: "newer", updatedAt: 2),
        ]

        XCTAssertTrue(viewModel.isAutomaticMenuBarProviderSelection)
        XCTAssertEqual(viewModel.menuBarProviderId, "first")

        viewModel.setAutomaticMenuBarProviderSelection(false)

        XCTAssertFalse(viewModel.isAutomaticMenuBarProviderSelection)
        XCTAssertFalse(MenuBarProviderSelectionPreferences.isAutomatic)
        XCTAssertEqual(viewModel.menuBarProviderId, "first")
    }

    func testChangingVintageMacSettingUpdatesTheViewModelAndPersistedPreference() {
        let viewModel = QuotaViewModel(registry: ProviderRegistry())

        XCTAssertFalse(viewModel.isVintageMacIconEnabled)

        viewModel.setVintageMacIconEnabled(true)

        XCTAssertTrue(viewModel.isVintageMacIconEnabled)
        XCTAssertTrue(VintageMacIcon.isEnabled)
    }

    func testActivityScoreChangesSelectionAtInjectedExpirationWithoutQuotaWork() async {
        let clock = ActivityTestClock(Date(timeIntervalSinceReferenceDate: 1000))
        let sleeper = ActivityExpirationRecorder()
        let viewModel = QuotaViewModel(
            registry: ProviderRegistry(),
            activityExpirationSleeper: { interval in
                try await sleeper.record(interval)
            },
            activityNow: { clock.date }
        )
        viewModel.configuredProviderIds = ["first", "second"]
        viewModel.enabledProviderIds = ["first", "second"]
        viewModel.providerStates = [
            "first": loadedState(for: "first"),
            "second": loadedState(for: "second"),
        ]

        _ = await sleeper.waitForIntervals(count: 0)
        viewModel.recordActivityObservation(
            for: "second",
            observation: observation([usage("window", 1)]),
            at: clock.date
        )
        viewModel.recordActivityObservation(
            for: "second",
            observation: observation([usage("window", 2)]),
            at: clock.date
        )

        XCTAssertEqual(viewModel.menuBarProviderId, "second")
        let intervals = await sleeper.waitForIntervals(count: 1)
        XCTAssertEqual(intervals, [600])

        clock.date = clock.date.addingTimeInterval(600)
        viewModel.handleActivityDidWake()

        XCTAssertEqual(viewModel.menuBarProviderId, "first")
        XCTAssertTrue(viewModel.activityRuntime.policy.activeScoreProviderIds.isEmpty)
    }

    func testFastEntryRemainsSelectedAfterFastModeEndsUntilScoreExpires() {
        let clock = ActivityTestClock(Date(timeIntervalSinceReferenceDate: 2000))
        let viewModel = QuotaViewModel(
            registry: ProviderRegistry(),
            activityExpirationSleeper: { _ in throw CancellationError() },
            activityNow: { clock.date }
        )
        viewModel.configuredProviderIds = ["first", "three", "four"]
        viewModel.enabledProviderIds = ["first", "three", "four"]
        viewModel.providerStates = [
            "first": loadedState(for: "first"),
            "three": loadedState(for: "three"),
            "four": loadedState(for: "four"),
        ]

        viewModel.setFastRefreshStatusVisible(true, for: "three")
        XCTAssertEqual(viewModel.menuBarProviderId, "three")

        viewModel.setFastRefreshStatusVisible(false, for: "three")
        XCTAssertEqual(viewModel.menuBarProviderId, "three")

        clock.date = clock.date.addingTimeInterval(1800)
        viewModel.handleActivityDidWake()
        XCTAssertEqual(viewModel.menuBarProviderId, "first")
    }

    func testManualSelectionUsesFirstProviderAndDoesNotKeepActivitySelection() {
        let clock = ActivityTestClock(Date(timeIntervalSinceReferenceDate: 3000))
        let viewModel = QuotaViewModel(
            registry: ProviderRegistry(),
            activityExpirationSleeper: { _ in throw CancellationError() },
            activityNow: { clock.date }
        )
        viewModel.configuredProviderIds = ["first", "second"]
        viewModel.enabledProviderIds = ["first", "second"]
        viewModel.providerStates = [
            "first": loadedState(for: "first"),
            "second": loadedState(for: "second"),
        ]

        viewModel.setFastRefreshStatusVisible(true, for: "second")
        XCTAssertEqual(viewModel.menuBarProviderId, "second")

        viewModel.setAutomaticMenuBarProviderSelection(false)

        XCTAssertEqual(viewModel.menuBarProviderId, "first")
    }

    func testSleepCancelsAndWakeReschedulesOneActivityExpiration() {
        let clock = ActivityTestClock(Date(timeIntervalSinceReferenceDate: 4000))
        let viewModel = QuotaViewModel(
            registry: ProviderRegistry(),
            activityExpirationSleeper: { _ in throw CancellationError() },
            activityNow: { clock.date }
        )
        viewModel.configuredProviderIds = ["provider"]
        viewModel.enabledProviderIds = ["provider"]
        viewModel.providerStates = ["provider": loadedState(for: "provider")]

        viewModel.setFastRefreshStatusVisible(true, for: "provider")
        XCTAssertNotNil(viewModel.activityRuntime.expirationTask)

        viewModel.handleActivityWillSleep()
        XCTAssertNil(viewModel.activityRuntime.expirationTask)

        viewModel.handleActivityDidWake()
        XCTAssertNotNil(viewModel.activityRuntime.expirationTask)
    }

    func testInvalidatingAProviderResetsItsActivityState() {
        let clock = ActivityTestClock(Date(timeIntervalSinceReferenceDate: 5000))
        let viewModel = QuotaViewModel(
            registry: ProviderRegistry(),
            activityExpirationSleeper: { _ in throw CancellationError() },
            activityNow: { clock.date }
        )
        viewModel.configuredProviderIds = ["first", "second"]
        viewModel.enabledProviderIds = ["first", "second"]
        viewModel.providerStates = [
            "first": loadedState(for: "first"),
            "second": loadedState(for: "second"),
        ]

        viewModel.setFastRefreshStatusVisible(true, for: "second")
        XCTAssertEqual(viewModel.menuBarProviderId, "second")

        viewModel.invalidateProviderWork(for: "second")

        XCTAssertEqual(viewModel.menuBarProviderId, "first")
        XCTAssertFalse(viewModel.activityRuntime.policy.activeScoreProviderIds.contains("second"))
        XCTAssertFalse(viewModel.activityRuntime.policy.baselineProviderIds.contains("second"))
    }

    private func loadedState(for providerId: String, updatedAt: TimeInterval) -> ProviderState {
        .loaded(
            ProviderQuota(
                providerId: providerId,
                providerName: providerId,
                headline: "",
                lines: [UsageLine(label: "Window", percentage: 20)],
                lastUpdated: Date(timeIntervalSinceReferenceDate: updatedAt)
            )
        )
    }

    private func loadedState(for providerId: String) -> ProviderState {
        loadedState(for: providerId, updatedAt: 0)
    }

    private func observation(_ metrics: [ProviderActivityMetric]) -> ProviderActivityObservation {
        ProviderActivityObservation(metrics: metrics)
    }

    private func usage(_ id: String, _ value: Int) -> ProviderActivityMetric {
        ProviderActivityMetric(id: id, kind: .usage, value: .number(Decimal(value)))
    }
}

private final class ActivityTestClock: @unchecked Sendable {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

private actor ActivityExpirationRecorder {
    private var intervals: [TimeInterval] = []

    func record(_ interval: TimeInterval) throws {
        intervals.append(interval)
        throw CancellationError()
    }

    func waitForIntervals(count: Int) async -> [TimeInterval] {
        for _ in 0 ..< 100 where intervals.count < count {
            await Task.yield()
        }
        return intervals
    }
}
