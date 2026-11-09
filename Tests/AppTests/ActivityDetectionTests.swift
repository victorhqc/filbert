@testable import App
import Core
import Foundation
import XCTest

private struct HooksFileFailure: Error, DiagnosticError, LocalizedError {
    var diagnosticCode: String {
        "hooks-file-unreadable"
    }

    var errorDescription: String? {
        "SECRET file content"
    }
}

@MainActor
final class ActivityDetectionTests: XCTestCase {
    private let suiteName = "filbert.tests.activity-detection"
    private let providerId = ActivityDetectionSpyProvider.providerId
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(defaults)
        AutoRefreshPreferences.setUserDefaults(defaults)
        ActivityDetectionNoticeDismissals.setUserDefaults(defaults)
        ProviderEnablement.setEnabled(true, for: providerId)
        AutoRefreshPreferences.setEnabled(true, for: providerId)
        AutoRefreshPreferences.mode = .smart
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(.standard)
        AutoRefreshPreferences.setUserDefaults(.standard)
        ActivityDetectionNoticeDismissals.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Presentation

    func testEachStatusMapsToItsSummaryDetailAndAction() {
        let off = ActivityDetectionPresentation(status: .notInstalled(nil), providerName: "Codex")
        XCTAssertEqual(off.summary, "Off")
        XCTAssertNil(off.detail)
        XCTAssertEqual(off.action, .install)

        let waiting = ActivityDetectionPresentation(
            status: .awaitingFirstSignal(DisplayText(verbatim: "Trust the hooks")),
            providerName: "Codex"
        )
        XCTAssertEqual(waiting.summary, "Installed. Finish setup in Codex")
        XCTAssertEqual(waiting.detail, "Trust the hooks")
        XCTAssertEqual(waiting.action, .remove)

        let active = ActivityDetectionPresentation(status: .active, providerName: "Codex")
        XCTAssertEqual(active.summary, "On")
        XCTAssertNil(active.detail)
        XCTAssertEqual(active.action, .remove)

        let unavailable = ActivityDetectionPresentation(
            status: .unavailable(DisplayText(verbatim: "No client")),
            providerName: "Codex"
        )
        XCTAssertEqual(unavailable.summary, "No client")
        XCTAssertNil(unavailable.detail)
        XCTAssertNil(unavailable.action)
    }

    func testANotInstalledReasonIsShownAsTheDetail() {
        let presentation = ActivityDetectionPresentation(
            status: .notInstalled(DisplayText(verbatim: "Unreadable")),
            providerName: "Codex"
        )

        XCTAssertEqual(presentation.detail, "Unreadable")
        XCTAssertEqual(presentation.action, .install)
    }

    // MARK: - Settings destination

    func testOpeningADestinationSelectsTheTabAndKeepsTheProviderUntilTaken() {
        let navigation = SettingsNavigation()

        navigation.open(SettingsDestination(tab: .providers, providerId: providerId))

        XCTAssertEqual(navigation.selectedTab, .providers)
        XCTAssertEqual(navigation.pendingProviderId, providerId)
        XCTAssertEqual(navigation.takePendingProviderId(), providerId)
        XCTAssertNil(navigation.pendingProviderId)
        XCTAssertNil(navigation.takePendingProviderId())
    }

    func testOpeningATabAloneClearsAnyPendingProvider() {
        let navigation = SettingsNavigation()
        navigation.open(SettingsDestination(tab: .providers, providerId: providerId))

        navigation.open(SettingsDestination(tab: .refresh))

        XCTAssertEqual(navigation.selectedTab, .refresh)
        XCTAssertNil(navigation.pendingProviderId)
    }

    // MARK: - Model

    func testStatusesComeFromTheRegistryAndADisabledProviderHasNone() async {
        let provider = ActivityDetectionSpyProvider()
        provider.status = .active
        let (model, registry) = makeModel(provider: provider)

        await model.refreshStatuses(for: [providerId])
        XCTAssertTrue(isActive(model.statuses[providerId]))

        registry.setEnabled(false, for: providerId)
        await model.refreshStatuses(for: [providerId])
        XCTAssertNil(model.statuses[providerId])
    }

    func testInstallRefreshesTheStatusAndClearsADismissal() async {
        let provider = ActivityDetectionSpyProvider()
        let (model, _) = makeModel(provider: provider)
        model.dismissNotice(for: providerId)
        XCTAssertTrue(model.dismissedProviderIds.contains(providerId))

        await model.install(for: providerId)

        XCTAssertEqual(provider.installCallCount, 1)
        XCTAssertTrue(model.isAwaitingFirstSignal(providerId))
        XCTAssertFalse(model.dismissedProviderIds.contains(providerId))
        XCTAssertFalse(ActivityDetectionNoticeDismissals.providerIds.contains(providerId))
        XCTAssertTrue(model.busyProviderIds.isEmpty)
    }

    func testRemoveRefreshesTheStatus() async {
        let provider = ActivityDetectionSpyProvider()
        provider.status = .active
        let (model, _) = makeModel(provider: provider)

        await model.remove(for: providerId)

        XCTAssertEqual(provider.removeCallCount, 1)
        XCTAssertTrue(isNotInstalled(model.statuses[providerId]))
    }

    func testADismissalSurvivesANewModel() {
        let provider = ActivityDetectionSpyProvider()
        let (model, _) = makeModel(provider: provider)

        model.dismissNotice(for: providerId)
        let (relaunched, _) = makeModel(provider: provider)

        XCTAssertTrue(relaunched.dismissedProviderIds.contains(providerId))
    }

    func testAFailedInstallShowsTheErrorAndLogsOnlyItsCode() async throws {
        let provider = ActivityDetectionSpyProvider()
        provider.installError = HooksFileFailure()
        let errorLog = AppTestErrorLog.make()
        let (model, _) = makeModel(provider: provider, errorLog: errorLog)
        model.dismissNotice(for: providerId)

        await model.install(for: providerId)

        XCTAssertEqual(model.errors[providerId]?.resolved, "SECRET file content")
        XCTAssertTrue(isNotInstalled(model.statuses[providerId]))
        XCTAssertTrue(model.dismissedProviderIds.contains(providerId))
        let text = try String(contentsOf: errorLog.fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("SECRET"))
        XCTAssertTrue(text.contains("install-activity-signal"))
        XCTAssertTrue(text.contains("hooks-file-unreadable"))
    }

    func testASuccessfulRetryClearsTheError() async {
        let provider = ActivityDetectionSpyProvider()
        provider.installError = HooksFileFailure()
        let (model, _) = makeModel(provider: provider)
        await model.install(for: providerId)
        XCTAssertNotNil(model.errors[providerId])

        provider.installError = nil
        await model.install(for: providerId)

        XCTAssertNil(model.errors[providerId])
    }

    // MARK: - Popover notice

    func testTheNoticeShowsWhileAnInstallAwaitsItsFirstSignal() async {
        let provider = ActivityDetectionSpyProvider()
        provider.status = .awaitingFirstSignal(nil)
        let viewModel = await makeLoadedViewModel(provider: provider)

        await viewModel.activityDetection.refreshStatuses(for: [providerId])

        XCTAssertTrue(viewModel.showsActivityDetectionNotice(for: providerId))
    }

    func testTheNoticeNeverPromptsAUserWhoHasNotOptedIn() async {
        let provider = ActivityDetectionSpyProvider()
        let viewModel = await makeLoadedViewModel(provider: provider)

        for status in [
            ActivitySignalStatus.notInstalled(nil),
            .active,
            .unavailable(DisplayText(verbatim: "No client")),
        ] {
            provider.status = status
            await viewModel.activityDetection.refreshStatuses(for: [providerId])
            XCTAssertFalse(viewModel.showsActivityDetectionNotice(for: providerId), "\(status)")
        }
    }

    func testTheNoticeHidesWhenSignalsWouldHaveNoEffect() async {
        let provider = ActivityDetectionSpyProvider()
        provider.status = .awaitingFirstSignal(nil)
        let viewModel = await makeLoadedViewModel(provider: provider)
        await viewModel.activityDetection.refreshStatuses(for: [providerId])

        viewModel.setAutoRefreshMode(.regular)
        XCTAssertFalse(viewModel.showsActivityDetectionNotice(for: providerId))
        XCTAssertFalse(viewModel.activityDetectionTakesEffect(for: providerId))

        viewModel.setAutoRefreshMode(.smart)
        viewModel.setAutoRefreshEnabled(false, for: providerId)
        XCTAssertFalse(viewModel.showsActivityDetectionNotice(for: providerId))
        XCTAssertFalse(viewModel.activityDetectionTakesEffect(for: providerId))
    }

    func testNotNowHidesTheNoticeAndANewInstallBringsItBack() async {
        let provider = ActivityDetectionSpyProvider()
        provider.status = .awaitingFirstSignal(nil)
        let viewModel = await makeLoadedViewModel(provider: provider)
        await viewModel.activityDetection.refreshStatuses(for: [providerId])

        viewModel.activityDetection.dismissNotice(for: providerId)
        XCTAssertFalse(viewModel.showsActivityDetectionNotice(for: providerId))

        await viewModel.activityDetection.install(for: providerId)
        XCTAssertTrue(viewModel.showsActivityDetectionNotice(for: providerId))
    }

    // MARK: - Helpers

    private func isActive(_ status: ActivitySignalStatus?) -> Bool {
        if case .active = status {
            return true
        }
        return false
    }

    private func isNotInstalled(_ status: ActivitySignalStatus?) -> Bool {
        if case .notInstalled = status {
            return true
        }
        return false
    }

    private func makeModel(
        provider: ActivityDetectionSpyProvider,
        errorLog: ErrorLog = AppTestErrorLog.make()
    ) -> (ActivityDetectionModel, ProviderRegistry) {
        let registry = ProviderRegistry()
        registry.register(provider)
        return (ActivityDetectionModel(registry: registry, errorLog: errorLog), registry)
    }

    private func makeLoadedViewModel(provider: ActivityDetectionSpyProvider) async -> QuotaViewModel {
        let registry = ProviderRegistry()
        registry.register(provider)
        let viewModel = QuotaViewModel(
            registry: registry,
            errorLog: AppTestErrorLog.make(),
            autoRefreshSleeper: { _ in throw CancellationError() },
            smartRefreshBoundarySleeper: { _ in throw CancellationError() },
            networkPath: TestNetworkPath(),
            wakeNetworkSleeper: { _ in throw CancellationError() },
            retryGateExpirySleeper: { _ in throw CancellationError() }
        )
        await waitUntil {
            if case .loaded = viewModel.providerStates[self.providerId] {
                return true
            }
            return false
        }
        return viewModel
    }
}

private final class ActivityDetectionSpyProvider: AIProvider, ActivitySignaling, @unchecked Sendable {
    static let providerId = "activity-detection-spy"
    static let providerName = "Activity Detection Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    private let lock = NSLock()
    private var storedStatus = ActivitySignalStatus.notInstalled(nil)
    private var storedInstallError: (any Error)?
    private var installs = 0
    private var removals = 0

    var status: ActivitySignalStatus {
        get { lock.withLock { storedStatus } }
        set { lock.withLock { storedStatus = newValue } }
    }

    var installError: (any Error)? {
        get { lock.withLock { storedInstallError } }
        set { lock.withLock { storedInstallError = newValue } }
    }

    var installCallCount: Int {
        lock.withLock { installs }
    }

    var removeCallCount: Int {
        lock.withLock { removals }
    }

    func isConfigured() -> Bool {
        true
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: DisplayText(verbatim: "10%"),
            lines: [UsageLine(label: DisplayText(verbatim: "Usage"), percentage: 10)],
            lastUpdated: Date()
        )
    }

    func activitySignals() -> AsyncStream<Date> {
        AsyncStream { _ in }
    }

    func activitySignalStatus() async -> ActivitySignalStatus {
        status
    }

    func installActivitySignal() async throws {
        try lock.withLock {
            installs += 1
            if let storedInstallError {
                throw storedInstallError
            }
            storedStatus = .awaitingFirstSignal(nil)
        }
    }

    func removeActivitySignal() async throws {
        lock.withLock {
            removals += 1
            storedStatus = .notInstalled(nil)
        }
    }
}
