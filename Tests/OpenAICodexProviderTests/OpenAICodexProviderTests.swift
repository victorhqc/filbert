import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexProviderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
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
        XCTAssertEqual(message, "Codex CLI not installed")
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

        let result = try await CodexAppServerClient(timeout: 2).readRateLimits(at: executable.path)

        XCTAssertEqual(result.rateLimits?.primary?.usedPercent, 32)
        XCTAssertEqual(result.rateLimits?.primary?.windowDurationMins, 300)
        XCTAssertEqual(result.rateLimits?.credits?.balance, "12.50")
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
                    secondary: CodexRateLimitWindow(usedPercent: 40, resetsAt: 4000, windowDurationMins: 1440),
                    credits: CodexCredits(balance: "12.5", unlimited: false)
                ),
            ]
        )

        let quota = provider.map(result)

        XCTAssertEqual(quota.lines.count, 2)
        XCTAssertEqual(quota.lines[0].percentage, 20)
        XCTAssertEqual(quota.lines[0].label, "60-minute window")
        XCTAssertEqual(quota.lines[0].resetDate, Date(timeIntervalSince1970: 3000))
        XCTAssertNil(quota.lines[0].used)
        XCTAssertNil(quota.lines[0].total)
        XCTAssertNil(quota.lines[0].unit)
        XCTAssertEqual(quota.lines[0].details?.first?.label, "Credits")
        XCTAssertEqual(quota.lines[0].details?.first?.value, "12.5")
        XCTAssertTrue(quota.headline.hasPrefix("20%"))
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "primary-window-usage", kind: .usage, value: .number(20)),
            ProviderActivityMetric(id: "secondary-window-usage", kind: .usage, value: .number(40)),
            ProviderActivityMetric(id: "credits", kind: .credits, value: .number(12.5)),
        ])
    }

    func testProvider_omitsMissingWindowsAndUsesUnlimitedCredits() {
        let provider = makeProvider(executablePath: nil)
        let result = CodexRateLimitReadResult(
            rateLimits: CodexRateLimitSnapshot(
                primary: nil,
                secondary: nil,
                credits: CodexCredits(balance: nil, unlimited: true)
            ),
            rateLimitsByLimitId: nil
        )

        let quota = provider.map(result)

        XCTAssertEqual(quota.headline, "No usage limits reported")
        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].label, "Credits")
        XCTAssertEqual(quota.lines[0].details?.first?.value, "Unlimited credits")
        XCTAssertEqual(quota.activityObservation?.metrics, [
            ProviderActivityMetric(id: "credits", kind: .credits, value: .discrete("unlimited")),
        ])
    }

    // MARK: - coalesced fetches

    func testProvider_coalescesConcurrentFetches() async throws {
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

        async let first = provider.fetchQuota(auth: .apiKeyFree, baseURL: OpenAICodexProvider.baseURL)
        async let second = provider.fetchQuota(auth: .apiKeyFree, baseURL: OpenAICodexProvider.baseURL)
        _ = try await (first, second)

        let invocations = try String(contentsOf: countURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(invocations.count, 1)
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
            client: CodexAppServerClient(timeout: 2)
        )
    }

    private func assertClientError(
        _ expected: CodexAppServerError,
        executable: URL,
        timeout: TimeInterval = 2
    ) async {
        do {
            _ = try await CodexAppServerClient(timeout: timeout).readRateLimits(at: executable.path)
            XCTFail("Expected \(expected)")
        } catch let error as CodexAppServerError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func serverBody(response: String) -> String {
        """
        read _
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        read _
        read _
        \(response)
        """
    }

    private func writeServer(name: String, body: String) throws -> URL {
        let executable = temporaryDirectory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }
}
