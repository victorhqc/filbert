@testable import App
import Core
import Foundation
import Security
import XCTest

@MainActor
final class ErrorLoggingViewModelTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "filbert.tests.error-logging.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        ProviderEnablement.setUserDefaults(defaults)
        AutoRefreshPreferences.setUserDefaults(defaults)
        ProviderEnablement.setEnabled(true, for: ErrorLoggingProvider.providerId)
    }

    override func tearDownWithError() throws {
        ProviderEnablement.setUserDefaults(.standard)
        AutoRefreshPreferences.setUserDefaults(.standard)
        defaults.removePersistentDomain(forName: suiteName)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testSuccessfulSetupFetchAndRefreshCreateNoLog() async {
        let (viewModel, _) = makeViewModel()
        await waitForIdle(viewModel)
        viewModel.manualRefresh(for: ErrorLoggingProvider.providerId)
        await waitForIdle(viewModel)

        XCTAssertFalse(FileManager.default.fileExists(atPath: viewModel.errorLog.fileURL.path))
        XCTAssertNil(viewModel.refreshErrors[ErrorLoggingProvider.providerId])
    }

    func testFetchFailureLogsOnceAndRetainsPreviousResults() async throws {
        let (viewModel, provider) = makeViewModel()
        await waitForIdle(viewModel)
        await provider.failFetch()

        viewModel.manualRefresh(for: ErrorLoggingProvider.providerId)
        await waitForIdle(viewModel)

        let records = try records(viewModel.errorLog)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?["operation"] as? String, "fetch-quota")
        XCTAssertNotNil(viewModel.refreshErrors[ErrorLoggingProvider.providerId])
        guard case let .loaded(quota) = viewModel.providerStates[ErrorLoggingProvider.providerId] else {
            return XCTFail("Previous results must remain visible")
        }
        XCTAssertEqual(quota.lastUpdated, ErrorLoggingProvider.cacheDate)
        XCTAssertEqual(quota.headline, "Cached usage")
    }

    func testProactiveFailureSurvivesSuccessfulCacheReadAndClearsOnRecovery() async throws {
        let (viewModel, provider) = makeViewModel()
        await waitForIdle(viewModel)
        await provider.setRefreshFailure(.failed)

        viewModel.manualRefresh(for: ErrorLoggingProvider.providerId)
        await waitForIdle(viewModel)

        XCTAssertNotNil(viewModel.refreshErrors[ErrorLoggingProvider.providerId])
        XCTAssertEqual(try records(viewModel.errorLog).count, 1)
        guard case let .loaded(quota) = viewModel.providerStates[ErrorLoggingProvider.providerId] else {
            return XCTFail("Cache data must remain visible")
        }
        XCTAssertEqual(quota.lastUpdated, ErrorLoggingProvider.cacheDate)

        await provider.setRefreshFailure(.none)
        viewModel.manualRefresh(for: ErrorLoggingProvider.providerId)
        await waitForIdle(viewModel)

        XCTAssertNil(viewModel.refreshErrors[ErrorLoggingProvider.providerId])
        XCTAssertEqual(try records(viewModel.errorLog).count, 1)
    }

    func testCancelledAndUnsupportedRefreshesCreateNoLog() async {
        let (viewModel, provider) = makeViewModel()
        await waitForIdle(viewModel)
        for failure in [ErrorLoggingProvider.RefreshFailure.cancelled, .unsupported] {
            await provider.setRefreshFailure(failure)
            viewModel.manualRefresh(for: ErrorLoggingProvider.providerId)
            await waitForIdle(viewModel)
            XCTAssertNil(viewModel.refreshErrors[ErrorLoggingProvider.providerId])
        }
        XCTAssertNil(viewModel.errorLog.availableFileURL)
    }

    func testFetchCancellationRetainsDataWithoutAnErrorOrLog() async {
        let (viewModel, provider) = makeViewModel()
        await waitForIdle(viewModel)
        await provider.cancelFetch()

        viewModel.manualRefresh(for: ErrorLoggingProvider.providerId)
        await waitForIdle(viewModel)

        XCTAssertNil(viewModel.refreshErrors[ErrorLoggingProvider.providerId])
        XCTAssertNil(viewModel.errorLog.availableFileURL)
        XCTAssertTrue(viewModel.providerStates[ErrorLoggingProvider.providerId].isLoaded)
    }

    func testFirstFetchCancellationShowsRetryableNoDataWithoutAnError() async {
        let (viewModel, provider) = makeViewModel(fetchCancellation: true)
        await waitForIdle(viewModel)
        let id = ErrorLoggingProvider.providerId
        XCTAssertNil(viewModel.refreshErrors[id])
        XCTAssertNil(viewModel.errorLog.availableFileURL)
        guard case let .loaded(quota) = viewModel.providerStates[id] else {
            return XCTFail("Cancellation must not leave the initial spinner active")
        }
        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertNotNil(quota.error)

        await provider.setFetchFailure(.none)
        viewModel.manualRefresh(for: id)
        await waitForIdle(viewModel)

        guard case let .loaded(recoveredQuota) = viewModel.providerStates[id] else {
            return XCTFail("The user must be able to refresh after cancellation")
        }
        XCTAssertEqual(recoveredQuota.headline, "Cached usage")
        XCTAssertNil(recoveredQuota.error)
    }

    func testCancelledAndUnsupportedSetupOperationsRetainStateWithoutLogs() async {
        let (viewModel, provider) = makeViewModel()
        await waitForIdle(viewModel)
        for failure in [ErrorLoggingProvider.RefreshFailure.cancelled, .unsupported] {
            await provider.setSetupFailure(failure)
            await viewModel.installHelper(for: ErrorLoggingProvider.providerId)
            await viewModel.removeHelper(for: ErrorLoggingProvider.providerId)
            await viewModel.importCredentials(for: ErrorLoggingProvider.providerId)

            XCTAssertTrue(viewModel.providerStates[ErrorLoggingProvider.providerId].isLoaded)
            XCTAssertNil(viewModel.errorLog.availableFileURL)
        }
    }

    func testHelperAndCredentialFailuresHaveDistinctRecordsAndRemainRetryable() async throws {
        let (viewModel, _) = makeViewModel()
        await waitForIdle(viewModel)

        await viewModel.installHelper(for: ErrorLoggingProvider.providerId)
        XCTAssertTrue(viewModel.canRemoveHelper(for: ErrorLoggingProvider.providerId))
        await viewModel.removeHelper(for: ErrorLoggingProvider.providerId)
        await viewModel.importCredentials(for: ErrorLoggingProvider.providerId)

        let operations = try records(viewModel.errorLog).compactMap { $0["operation"] as? String }
        XCTAssertEqual(operations, ["install-helper", "remove-helper", "import-credentials"])
        let content = try String(contentsOf: viewModel.errorLog.fileURL, encoding: .utf8)
        XCTAssertFalse(content.contains("SECRET"))
        XCTAssertNotNil(viewModel.errorLog.availableFileURL)
        guard case .error = viewModel.providerStates[ErrorLoggingProvider.providerId] else {
            return XCTFail("The operation failure must remain visible")
        }
    }

    func testUnconfiguredHelperInstallationFailureCanBeRetriedSuccessfully() async throws {
        let (viewModel, provider) = makeViewModel(helperInstalled: false)
        await waitForIdle(viewModel)
        XCTAssertFalse(viewModel.isReadyToFetch(ErrorLoggingProvider.providerId))

        await viewModel.installHelper(for: ErrorLoggingProvider.providerId)

        XCTAssertTrue(viewModel.canInstallHelper(for: ErrorLoggingProvider.providerId))
        XCTAssertFalse(viewModel.isReadyToFetch(ErrorLoggingProvider.providerId))
        guard case .error = viewModel.providerStates[ErrorLoggingProvider.providerId] else {
            return XCTFail("Installation failure must remain visible")
        }

        await provider.setSetupFailure(.none)
        await viewModel.installHelper(for: ErrorLoggingProvider.providerId)
        await waitForIdle(viewModel)

        XCTAssertTrue(viewModel.providerStates[ErrorLoggingProvider.providerId].isLoaded)
        XCTAssertFalse(viewModel.canInstallHelper(for: ErrorLoggingProvider.providerId))
        XCTAssertTrue(viewModel.canRemoveHelper(for: ErrorLoggingProvider.providerId))
        XCTAssertEqual(try records(viewModel.errorLog).count, 1)
    }

    func testMissingCredentialsDoNotCreateAnErrorLog() async {
        let (viewModel, _) = makeViewModel()
        await waitForIdle(viewModel)
        let id = ErrorLoggingProvider.providerId
        viewModel.applyResults(
            [id: .failure(KeychainError.loadFailed(errSecItemNotFound))],
            expectedRevisions: [:],
            suppressSmartSuccessFor: []
        )
        XCTAssertNil(viewModel.errorLog.availableFileURL)
        XCTAssertNil(viewModel.refreshErrors[id])
        guard case .unconfigured = viewModel.providerStates[id] else {
            return XCTFail("Missing credentials must return to setup")
        }
    }

    func testUnavailableLogDoesNotHideOperationFailure() async throws {
        try Data().write(to: directory)
        let (viewModel, _) = makeViewModel()
        await waitForIdle(viewModel)

        await viewModel.installHelper(for: ErrorLoggingProvider.providerId)

        XCTAssertNil(viewModel.errorLog.availableFileURL)
        guard case .error = viewModel.providerStates[ErrorLoggingProvider.providerId] else {
            return XCTFail("The original failure must remain visible")
        }
    }

    private func makeViewModel(
        helperInstalled: Bool = true,
        fetchCancellation: Bool = false
    ) -> (QuotaViewModel, ErrorLoggingProvider) {
        let provider = ErrorLoggingProvider(
            helperInstalled: helperInstalled,
            fetchFailure: fetchCancellation ? .cancelled : .none
        )
        let registry = ProviderRegistry()
        registry.register(provider)
        let viewModel = QuotaViewModel(
            registry: registry,
            errorLog: ErrorLog(directoryURL: directory),
            autoRefreshSleeper: { _ in throw CancellationError() }
        )
        return (viewModel, provider)
    }

    private func waitForIdle(_ viewModel: QuotaViewModel) async {
        for _ in 0 ..< 1000 {
            if viewModel.setupTasks.isEmpty, viewModel.fetchTasks.isEmpty {
                return
            }
            await Task.yield()
        }
        XCTFail("Provider work did not finish")
    }

    private func records(_ log: ErrorLog) throws -> [[String: Any]] {
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("SECRET"))
        return try text.split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
    }
}

private extension ProviderState? {
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

private actor ErrorLoggingProvider: ProactiveRefreshable {
    static let providerId = "error-logging-fixture"
    static let providerName = "Error logging fixture"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let cacheDate = Date(timeIntervalSince1970: 1234)

    enum RefreshFailure {
        case none
        case failed
        case cancelled
        case unsupported
    }

    private var fetchFailure = RefreshFailure.none
    private var refreshFailure = RefreshFailure.none
    private var setupFailure = RefreshFailure.failed
    private let helper: HelperConfiguration

    init(helperInstalled: Bool, fetchFailure: RefreshFailure = .none) {
        helper = HelperConfiguration(isInstalled: helperInstalled)
        self.fetchFailure = fetchFailure
    }

    nonisolated func isConfigured() -> Bool {
        helper.isInstalled
    }

    nonisolated func canInstallHelper() -> Bool {
        !helper.isInstalled
    }

    nonisolated func canRemoveHelper() -> Bool {
        helper.isInstalled
    }

    func currentSetupState() async -> ProviderState? {
        helper.isInstalled ? nil : .setup("Helper not installed")
    }

    func failFetch() {
        fetchFailure = .failed
    }

    func cancelFetch() {
        fetchFailure = .cancelled
    }

    func setFetchFailure(_ failure: RefreshFailure) {
        fetchFailure = failure
    }

    func setRefreshFailure(_ failure: RefreshFailure) {
        refreshFailure = failure
    }

    func setSetupFailure(_ failure: RefreshFailure) {
        setupFailure = failure
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        try throwIfNeeded(fetchFailure)
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "Cached usage",
            lines: [],
            lastUpdated: Self.cacheDate
        )
    }

    func proactiveRefresh() async throws {
        try throwIfNeeded(refreshFailure)
    }

    private func throwIfNeeded(_ mode: RefreshFailure) throws {
        switch mode {
        case .none: return
        case .failed: throw failure()
        case .cancelled: throw CancellationError()
        case .unsupported: throw ProviderSetupError.notSupported
        }
    }

    func installHelper() async throws {
        try throwIfNeeded(setupFailure)
        helper.setInstalled(true)
    }

    func removeHelper() async throws {
        try throwIfNeeded(setupFailure)
        helper.setInstalled(false)
    }

    func importCredentials() async throws {
        try throwIfNeeded(setupFailure)
    }

    private func failure() -> NSError {
        NSError(
            domain: "SECRET-domain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "SECRET-description"]
        )
    }
}

private final class HelperConfiguration: @unchecked Sendable {
    private let lock = NSLock()
    private var installed: Bool

    init(isInstalled: Bool) {
        installed = isInstalled
    }

    var isInstalled: Bool {
        lock.withLock { installed }
    }

    func setInstalled(_ installed: Bool) {
        lock.withLock { self.installed = installed }
    }
}
