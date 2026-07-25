@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeProviderTests: XCTestCase {
    private var cacheURL: URL!
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-provider-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true
        )
        cacheURL = tmpDir.appendingPathComponent("claude-code.json")
    }

    override func tearDown() {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        tmpDir = nil
        cacheURL = nil
        super.tearDown()
    }

    // MARK: - Provider identity

    func testProviderId() {
        XCTAssertEqual(ClaudeCodeProvider.providerId, "claude-code")
    }

    func testAuthShape_isApiKeyFree() {
        XCTAssertEqual(
            ClaudeCodeProvider.authShape,
            ProviderAuth.Shape.apiKeyFree
        )
    }

    func testProvider_suppliesOfficialCLISetupHelp() throws {
        let setupHelp = try XCTUnwrap(ClaudeCodeProvider.setupHelp)

        XCTAssertEqual(setupHelp.linkLabel, "Install Claude Code")
        XCTAssertEqual(
            setupHelp.url,
            URL(string: "https://docs.claude.com/en/docs/claude-code/overview")
        )
    }

    @MainActor
    func testProvider_transportsSetupHelpThroughRegistry() throws {
        let registry = ProviderRegistry()
        registry.register(ClaudeCodeProvider())

        let info = try XCTUnwrap(registry.registeredProviders.first)

        XCTAssertEqual(info.setupHelp, try XCTUnwrap(ClaudeCodeProvider.setupHelp))
    }

    // MARK: - isConfigured does not touch Keychain

    func testIsConfigured_trueWhenBinaryFoundAndHelperInstalled() {
        let locator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude")
        let installer = makeInstaller(helperInstalled: true)
        let provider = makeProvider(locator: locator, installer: installer)
        XCTAssertTrue(provider.isConfigured())
    }

    func testIsConfigured_falseWhenBinaryNotFound() {
        let locator = ClaudeCodeLocator(injectedPath: nil)
        let installer = makeInstaller(helperInstalled: true)
        let provider = makeProvider(locator: locator, installer: installer)
        XCTAssertFalse(provider.isConfigured())
    }

    func testIsConfigured_falseWhenHelperNotInstalled() {
        let locator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude")
        let installer = makeInstaller(helperInstalled: false)
        let provider = makeProvider(locator: locator, installer: installer)
        XCTAssertFalse(provider.isConfigured())
    }

    // MARK: - currentSetupState reports binary and helper status

    func testCurrentSetupState_setupReasonWhenBinaryMissing() async {
        let locator = ClaudeCodeLocator(injectedPath: nil)
        let installer = makeInstaller(helperInstalled: true)
        let provider = makeProvider(locator: locator, installer: installer)
        let state = await provider.currentSetupState()
        guard case let .setup(reason) = state else {
            XCTFail("Expected .setup, got \(String(describing: state))")
            return
        }
        XCTAssertTrue(reason.contains("not found"))
    }

    func testCurrentSetupState_setupReasonWhenHelperNotInstalled() async {
        let locator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude")
        let installer = makeInstaller(helperInstalled: false)
        let provider = makeProvider(locator: locator, installer: installer)
        let state = await provider.currentSetupState()
        guard case let .setup(reason) = state else {
            XCTFail("Expected .setup, got \(String(describing: state))")
            return
        }
        XCTAssertTrue(reason.contains("not installed"))
    }

    func testCurrentSetupState_nilWhenBinaryFoundAndHelperInstalled() async {
        let locator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude")
        let installer = makeInstaller(helperInstalled: true)
        let provider = makeProvider(locator: locator, installer: installer)
        let state = await provider.currentSetupState()
        XCTAssertNil(state)
    }

    // MARK: - canInstallHelper gating logic

    func testCanInstallHelper_trueWhenBinaryFoundAndHelperNotInstalled() {
        let locator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude")
        let installer = makeInstaller(helperInstalled: false)
        let provider = makeProvider(locator: locator, installer: installer)
        XCTAssertTrue(provider.canInstallHelper())
    }

    func testCanInstallHelper_falseWhenBinaryMissing() {
        let locator = ClaudeCodeLocator(injectedPath: nil)
        let installer = makeInstaller(helperInstalled: false)
        let provider = makeProvider(locator: locator, installer: installer)
        XCTAssertFalse(provider.canInstallHelper())
    }

    func testCanInstallHelper_falseWhenHelperAlreadyInstalled() {
        let locator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude")
        let installer = makeInstaller(helperInstalled: true)
        let provider = makeProvider(locator: locator, installer: installer)
        XCTAssertFalse(provider.canInstallHelper())
    }

    // MARK: - internal-consistency assertion

    func testFetchQuota_throwsInternalInconsistencyForApiKey() async throws {
        let provider = makeProvider()
        do {
            _ = try await provider.fetchQuota(
                auth: .apiKey("fake-key"),
                baseURL: ClaudeCodeProvider.baseURL
            )
            XCTFail("Expected internalInconsistency")
        } catch let error as ClaudeCodeError {
            XCTAssertEqual(error, .internalInconsistency)
        }
    }

    // MARK: - no cache file → error quota

    func testFetchQuota_returnsErrorQuota_whenNoCache() async throws {
        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertEqual(quota.providerId, "claude-code")
        XCTAssertEqual(quota.headline, "No data")
        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertNotNil(quota.error)
        XCTAssertTrue(quota.error?.contains("Open Claude Code") ?? false)
    }

    // MARK: - both windows → two UsageLines

    func testFetchQuota_mapsBothWindows() async throws {
        try writeCache(fiveHourPct: 42, fiveHourReset: 1_713_127_600,
                       sevenDayPct: 60, sevenDayReset: 1_713_500_000)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertEqual(quota.lines.count, 2)
        XCTAssertEqual(quota.lines[0].label, "5-hour window")
        XCTAssertEqual(quota.lines[0].percentage, 42)
        let reset0 = try XCTUnwrap(quota.lines[0].resetDate)
        XCTAssertEqual(
            reset0.timeIntervalSince1970,
            1_713_127_600.0 as TimeInterval,
            accuracy: 0.5
        )
        XCTAssertEqual(quota.lines[1].label, "Weekly")
        XCTAssertEqual(quota.lines[1].percentage, 60)
    }

    // MARK: - only five_hour

    func testFetchQuota_mapsOnlyFiveHour() async throws {
        try writeCache(fiveHourPct: 15, fiveHourReset: 1_713_127_600,
                       sevenDayPct: nil, sevenDayReset: nil)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].label, "5-hour window")
        XCTAssertEqual(quota.lines[0].percentage, 15)
    }

    // MARK: - only seven_day

    func testFetchQuota_mapsOnlySevenDay() async throws {
        try writeCache(fiveHourPct: nil, fiveHourReset: nil,
                       sevenDayPct: 80, sevenDayReset: 1_713_500_000)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].label, "Weekly")
        XCTAssertEqual(quota.lines[0].percentage, 80)
    }

    // MARK: - no `used`, `total`, or `unit` synthesized

    func testFetchQuota_noSynthesizedFields() async throws {
        try writeCache(fiveHourPct: 42, fiveHourReset: 1_713_127_600,
                       sevenDayPct: 60, sevenDayReset: 1_713_500_000)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        for line in quota.lines {
            XCTAssertNil(line.used, "used should be nil for Claude Code")
            XCTAssertNil(line.total, "total should be nil for Claude Code")
            XCTAssertNil(line.unit, "unit should be nil for Claude Code")
        }
    }

    // MARK: - no rate_limits → "No data"

    func testFetchQuota_noDataWhenRateLimitsAbsent() async throws {
        let json = Data(#"{"written_at": 1713000000}"#.utf8)
        try json.write(to: cacheURL, options: .atomic)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertEqual(quota.headline, "No data")
        XCTAssertTrue(quota.lines.isEmpty)
    }

    // MARK: - headline priority (5-hour → weekly)

    func testFetchQuota_headlineUsesFiveHourPriority() async throws {
        try writeCache(fiveHourPct: 42, fiveHourReset: futureEpoch(),
                       sevenDayPct: 60, sevenDayReset: futureEpoch())

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertTrue(quota.headline.hasPrefix("42%"))
        XCTAssertTrue(quota.headline.contains("\u{00B7}"))
        XCTAssertTrue(quota.headline.contains("resets"))
    }

    func testFetchQuota_headlineFallsBackToWeekly() async throws {
        try writeCache(fiveHourPct: nil, fiveHourReset: nil,
                       sevenDayPct: 75, sevenDayReset: futureEpoch())

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertTrue(quota.headline.hasPrefix("75%"))
        XCTAssertTrue(quota.headline.contains("resets"))
    }

    // MARK: - isStale flag

    func testFetchQuota_isStaleTrue_whenCacheOlderThanFreshnessThreshold() async throws {
        let staleEpoch = Date().timeIntervalSince1970
            - ClaudeCodeProvider.freshnessThreshold - 60
        let store = StatuslineCacheStore(cacheURL: cacheURL)
        let cache = StatuslineCache(
            writtenAt: staleEpoch,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 50, resetsAt: futureEpoch()),
                sevenDay: nil
            )
        )
        try store.write(cache)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertTrue(quota.isStale, "isStale should be true for old cache")
    }

    func testFetchQuota_isStaleFalse_whenCacheIsFresh() async throws {
        let store = StatuslineCacheStore(cacheURL: cacheURL)
        let cache = StatuslineCache(
            writtenAt: Date().timeIntervalSince1970,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 50, resetsAt: futureEpoch()),
                sevenDay: nil
            )
        )
        try store.write(cache)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertFalse(quota.isStale, "isStale should be false for fresh cache")
    }

    // MARK: - lastUpdated derived from written_at

    func testFetchQuota_lastUpdatedMatchesWrittenAt() async throws {
        let epoch = 1_713_127_600 as TimeInterval
        let store = StatuslineCacheStore(cacheURL: cacheURL)
        let cache = StatuslineCache(
            writtenAt: epoch,
            rateLimits: RateLimits(
                fiveHour: Window(usedPercentage: 42, resetsAt: epoch + 3600),
                sevenDay: nil
            )
        )
        try store.write(cache)

        let provider = makeProvider()
        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        XCTAssertEqual(
            quota.lastUpdated.timeIntervalSince1970,
            epoch,
            accuracy: 0.5
        )
    }

    // MARK: - ZAI orthogonality

    func testZAIProvider_isUnaffected() {
        let shape = ProviderAuth.Shape.apiKey
        XCTAssertEqual(shape, .apiKey)

        let quota = ProviderQuota(
            providerId: "zai",
            providerName: "z.ai",
            headline: "test",
            lines: [],
            lastUpdated: Date()
        )
        XCTAssertFalse(quota.isStale)
    }

    // MARK: - Helpers

    private func makeProvider(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(
            injectedPath: "/usr/local/bin/claude"
        ),
        installer: StatuslineHelperInstaller? = nil
    ) -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            locator: locator,
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            installer: installer ?? makeInstaller(helperInstalled: true)
        )
    }

    private func makeInstaller(helperInstalled: Bool) -> StatuslineHelperInstaller {
        let helperURL: URL = if helperInstalled {
            // Use a known executable so isHelperInstalled() returns true.
            URL(fileURLWithPath: "/bin/sh")
        } else {
            tmpDir.appendingPathComponent("nonexistent-helper")
        }
        return StatuslineHelperInstaller(
            settingsURL: tmpDir.appendingPathComponent("settings.json"),
            helperDestURL: helperURL,
            cacheURL: cacheURL
        )
    }

    private func writeCache(
        fiveHourPct: Double?,
        fiveHourReset: TimeInterval?,
        sevenDayPct: Double?,
        sevenDayReset: TimeInterval?
    ) throws {
        let store = StatuslineCacheStore(cacheURL: cacheURL)

        let fiveHour: Window? = if let pct = fiveHourPct, let reset = fiveHourReset {
            Window(usedPercentage: pct, resetsAt: reset)
        } else {
            nil
        }

        let sevenDay: Window? = if let pct = sevenDayPct, let reset = sevenDayReset {
            Window(usedPercentage: pct, resetsAt: reset)
        } else {
            nil
        }

        let rateLimits: RateLimits? = if fiveHour != nil || sevenDay != nil {
            RateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
        } else {
            nil
        }

        let cache = StatuslineCache(
            writtenAt: Date().timeIntervalSince1970,
            rateLimits: rateLimits
        )
        try store.write(cache)
    }

    private func futureEpoch() -> TimeInterval {
        Date().addingTimeInterval(3600).timeIntervalSince1970
    }
}
