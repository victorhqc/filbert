import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexProviderTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUpWithError() throws {
        DisplayLanguage.selectedLanguageCode = "en"
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        DisplayLanguage.selectedLanguageCode = nil
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - locator ordering

    func testLocator_prefersPATHBeforeKnownLocations() {
        let expectedPath = "/custom/bin/codex"
        let locator = CodexLocator(
            environment: ["PATH": "/custom/bin:/opt/homebrew/bin", "HOME": "/test"],
            isExecutable: { $0 == expectedPath || $0 == "/opt/homebrew/bin/codex" }
        )

        XCTAssertEqual(locator.resolve(), expectedPath)
    }

    func testLocator_findsMiseShimWhenNotOnPATH() {
        let expectedPath = "/test/.local/share/mise/shims/codex"
        let locator = CodexLocator(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/test"],
            isExecutable: { $0 == expectedPath }
        )

        XCTAssertEqual(locator.resolve(), expectedPath)
    }

    func testLocator_honorsMiseDataDirOverride() {
        let expectedPath = "/opt/mise-data/shims/codex"
        let locator = CodexLocator(
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": "/test",
                "MISE_DATA_DIR": "/opt/mise-data",
            ],
            isExecutable: { $0 == expectedPath }
        )

        XCTAssertEqual(locator.resolve(), expectedPath)
    }

    func testLocator_returnsNilWhenNoExecutableExists() {
        let locator = CodexLocator(
            environment: ["PATH": "/custom/bin", "HOME": "/test"],
            isExecutable: { _ in false }
        )

        XCTAssertNil(locator.resolve())
    }

    // MARK: - API-key-free setup

    func testProvider_reportsMissingCLIAsSetupState() async {
        let provider = makeProvider(executablePath: nil)

        XCTAssertEqual(OpenAICodexProvider.authShape, .apiKeyFree)
        XCTAssertFalse(provider.isConfigured())
        guard case let .setup(message) = await provider.currentSetupState() else {
            return XCTFail("Expected setup state")
        }
        XCTAssertEqual(message.resolved, "Codex CLI not installed")
    }

    func testProvider_suppliesOfficialCLISetupHelp() throws {
        let setupHelp = try XCTUnwrap(OpenAICodexProvider.setupHelp)

        XCTAssertEqual(setupHelp.linkLabel, "Install Codex CLI")
        XCTAssertEqual(setupHelp.url, URL(string: "https://developers.openai.com/codex/cli/"))
    }

    @MainActor
    func testProvider_transportsSetupHelpThroughRegistry() throws {
        let registry = ProviderRegistry()
        registry.register(OpenAICodexProvider())

        let info = try XCTUnwrap(registry.registeredProviders.first)

        XCTAssertEqual(info.setupHelp, try XCTUnwrap(OpenAICodexProvider.setupHelp))
    }

    // MARK: - protocol correlation and recoveries

    func testClient_ignoresNotificationsAndReturnsMatchingRateLimitResponse() async throws {
        let rateLimitResult = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":"
            + "{\"rateLimits\":{\"primary\":{\"usedPercent\":32,\"resetsAt\":2000,"
            + "\"windowDurationMins\":300},\"credits\":{\"balance\":\"12.50\","
            + "\"hasCredits\":true,\"unlimited\":false}}}}"
        let executable = try writeServer(
            name: "codex-notification",
            body: """
            read _
            printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
            read _
            read request
            case "$request" in
              *'"params":null'*) ;;
              *) printf '%s\\n' '{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"invalid params"}}'; exit ;;
            esac
            printf '%s\\n' '{"jsonrpc":"2.0","method":"account/rateLimits/updated","params":{"ignored":true}}'
            printf '%s\\n' '\(rateLimitResult)'
            """
        )

        let errorLog = makeErrorLog()
        let result = try await CodexAppServerClient(timeout: 2, errorLog: errorLog)
            .readRateLimits(at: executable.path)

        XCTAssertEqual(result.rateLimits?.primary?.usedPercent, 32)
        XCTAssertEqual(result.rateLimits?.primary?.windowDurationMins, 300)
        XCTAssertEqual(result.rateLimits?.credits?.balance, "12.50")
        XCTAssertEqual(result.rateLimits?.credits?.hasCredits, true)
        XCTAssertNil(errorLog.availableFileURL)
    }

    func testClient_mapsUnsupportedAndSignedOutErrorsWithoutPayloads() async throws {
        let unsupportedResponse = "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":"
            + "{\"code\":-32601,\"message\":\"method missing\"}}"
        let signedOutResponse = "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":"
            + "{\"code\":-32000,\"message\":\"please login\"}}"
        let unsupported = try writeServer(
            name: "codex-unsupported",
            body: serverBody(
                response: "printf '%s\\n' '\(unsupportedResponse)'"
            )
        )
        let signedOut = try writeServer(
            name: "codex-signed-out",
            body: serverBody(
                response: "printf '%s\\n' '\(signedOutResponse)'"
            )
        )

        await assertClientError(.unsupportedVersion, executable: unsupported)
        await assertClientError(.signedOut, executable: signedOut)
    }

    func testClient_timesOutAndTerminatesHungChild() async throws {
        let executable = try writeServer(
            name: "codex-hang",
            body: """
            read _
            sleep 60
            """
        )

        let start = Date()
        await assertClientError(.timedOut, executable: executable, timeout: 0.2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    // MARK: - snapshot mapping

    func testProvider_prefersCodexBucketAndMapsWindowsCreditsAndHeadline() {
        let provider = makeProvider(executablePath: nil)
        let result = CodexRateLimitReadResult(
            rateLimits: CodexRateLimitSnapshot(
                primary: CodexRateLimitWindow(usedPercent: 99, resetsAt: 2000, windowDurationMins: 300),
                secondary: nil,
                credits: nil
            ),
            rateLimitsByLimitId: [
                "codex": CodexRateLimitSnapshot(
                    primary: CodexRateLimitWindow(usedPercent: 20, resetsAt: 3000, windowDurationMins: 60),
                    secondary: CodexRateLimitWindow(usedPercent: 40, resetsAt: 4000, windowDurationMins: 10080),
                    credits: CodexCredits(hasCredits: true, balance: "12.5", unlimited: false)
                ),
            ]
        )

        let quota = provider.map(result, receivedAt: Date())

        XCTAssertEqual(quota.lines.map(\.id), ["primary-window-usage", "secondary-window-usage", "credits"])
        XCTAssertEqual(quota.lines[0].percentage, 20)
        XCTAssertEqual(quota.lines[0].label.resolved, "60-minute window")
        XCTAssertEqual(quota.lines[0].resetDate, Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(quota.lines[0].windowDuration, 60 * 60)
        XCTAssertEqual(quota.lines[1].windowDuration, UsageWindowDuration.week)
        XCTAssertNil(quota.lines[0].used)
        XCTAssertNil(quota.lines[0].total)
        XCTAssertNil(quota.lines[0].unit)
        XCTAssertNil(quota.lines[0].details)
        XCTAssertEqual(quota.lines[2].balance, UsageBalance(amount: .finite(12.5), unit: .credits))
        XCTAssertTrue(quota.headline.resolved.hasPrefix("20%"))
        XCTAssertEqual(
            quota.activityObservation?.metrics.map(\.value),
            [.number(20), .number(40), .number(12.5)]
        )
    }

    func testProvider_omitsMissingWindowsAndUsesUnlimitedCredits() {
        let provider = makeProvider(executablePath: nil)
        let result = CodexRateLimitReadResult(
            rateLimits: CodexRateLimitSnapshot(
                primary: nil,
                secondary: nil,
                credits: CodexCredits(hasCredits: true, balance: nil, unlimited: true)
            ),
            rateLimitsByLimitId: nil
        )

        let quota = provider.map(result, receivedAt: Date())

        XCTAssertEqual(quota.headline.resolved, "No usage limits reported")
        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].label.resolved, "Credits")
        XCTAssertEqual(quota.lines[0].balance, UsageBalance(amount: .unlimited, unit: .credits))
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "credits", kind: .credits, value: .discrete("unlimited")),
        ])
    }

    // MARK: - coalesced fetches

    func testProvider_coalescesConcurrentFetchesIntoOneReceiptTime() async throws {
        let countURL = temporaryDirectory.appendingPathComponent("count")
        let rateLimitResult = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":"
            + "{\"rateLimits\":{\"primary\":{\"usedPercent\":25,\"windowDurationMins\":300}}}}"
        let executable = try writeServer(
            name: "codex",
            body: """
            echo invocation >> '\(countURL.path)'
            read _
            printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
            read _
            read _
            sleep 0.2
            printf '%s\\n' '\(rateLimitResult)'
            """
        )
        let provider = makeProvider(executablePath: executable.path)

        let start = Date()
        async let first = provider.fetchQuota(auth: .apiKeyFree, baseURL: OpenAICodexProvider.baseURL)
        async let second = provider.fetchQuota(auth: .apiKeyFree, baseURL: OpenAICodexProvider.baseURL)
        let quotas = try await (first, second)
        let end = Date()

        let invocations = try String(contentsOf: countURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(quotas.0.lastUpdated, quotas.1.lastUpdated)
        XCTAssertTrue((start ... end).contains(quotas.0.lastUpdated))
    }

    private func makeProvider(executablePath: String?) -> OpenAICodexProvider {
        let environment = executablePath.map {
            ["PATH": URL(fileURLWithPath: $0).deletingLastPathComponent().path]
        } ?? [:]
        return OpenAICodexProvider(
            locator: CodexLocator(
                environment: environment,
                isExecutable: { $0 == executablePath }
            ),
            client: CodexAppServerClient(timeout: 2, errorLog: makeErrorLog())
        )
    }

    private func assertClientError(
        _ expected: CodexAppServerError,
        executable: URL,
        timeout: TimeInterval = 2
    ) async {
        do {
            _ = try await CodexAppServerClient(timeout: timeout, errorLog: makeErrorLog())
                .readRateLimits(at: executable.path)
            XCTFail("Expected \(expected)")
        } catch let error as CodexAppServerFailure {
            XCTAssertEqual(error.reason, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func makeErrorLog() -> ErrorLog {
        ErrorLog(directoryURL: temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func writeServer(name: String, body: String) throws -> URL {
        let executable = temporaryDirectory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }
}
