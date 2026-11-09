import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

private actor SignalCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

extension OpenAICodexProviderTests {
    private var signalURL: URL {
        temporaryDirectory.appendingPathComponent("cache/filbert/codex-activity")
    }

    private var testLatency: TimeInterval {
        0.2
    }

    func testWatcherCoalescesABurstIntoOneSignal() async throws {
        let (counter, task) = await startCounting(CodexActivityWatcher.signals(for: signalURL, latency: testLatency))
        defer { task.cancel() }

        for _ in 0 ..< 3 {
            try touchSignalFile()
        }
        await waitUntil { await counter.count >= 1 }
        try await Task.sleep(for: .milliseconds(600))

        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testWatcherSurvivesDeletionAndIgnoresIt() async throws {
        let (counter, task) = await startCounting(CodexActivityWatcher.signals(for: signalURL, latency: testLatency))
        defer { task.cancel() }

        try touchSignalFile()
        await waitUntil { await counter.count >= 1 }
        try await Task.sleep(for: .milliseconds(400))

        try FileManager.default.removeItem(at: signalURL)
        try await Task.sleep(for: .milliseconds(600))
        let afterDeletion = await counter.count
        XCTAssertEqual(afterDeletion, 1)

        try touchSignalFile()
        await waitUntil { await counter.count >= 2 }
        let afterRecreation = await counter.count
        XCTAssertEqual(afterRecreation, 2)
    }

    func testWatcherSignalsWhenAnExistingFileIsTouchedAgain() async throws {
        try touchSignalFile()
        let (counter, task) = await startCounting(CodexActivityWatcher.signals(for: signalURL, latency: testLatency))
        defer { task.cancel() }

        try touchSignalFile()
        await waitUntil { await counter.count >= 1 }
        try await Task.sleep(for: .milliseconds(400))
        try touchSignalFile()
        await waitUntil { await counter.count >= 2 }

        let count = await counter.count
        XCTAssertEqual(count, 2)
    }

    func testAUsageFetchProducesNoSignal() async throws {
        let rateLimitResult = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":"
            + "{\"rateLimits\":{\"primary\":{\"usedPercent\":12,\"windowDurationMins\":300}}}}"
        let executable = try writeServer(
            name: "codex",
            body: serverBody(response: "printf '%s\\n' '\(rateLimitResult)'")
        )
        let provider = makeSignalingProvider(codexPath: executable.path)
        try await provider.installActivitySignal()
        let (counter, task) = await startCounting(CodexActivityWatcher.signals(for: signalURL, latency: testLatency))
        defer { task.cancel() }

        _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: OpenAICodexProvider.baseURL)
        try await Task.sleep(for: .milliseconds(800))

        let count = await counter.count
        XCTAssertEqual(count, 0)
    }

    func testSignalStatusIsUnavailableWithoutTheCodexBinary() async throws {
        let provider = makeSignalingProvider(codexPath: nil)

        guard case let .unavailable(reason) = await provider.activitySignalStatus() else {
            return XCTFail("Expected unavailable")
        }
        XCTAssertEqual(reason.resolved, "Codex CLI not installed")
        do {
            try await provider.installActivitySignal()
            XCTFail("Expected binaryNotFound")
        } catch {
            XCTAssertEqual(error as? OpenAICodexError, .binaryNotFound)
        }
    }

    func testSignalStatusAndSetupStateAreIndependent() async throws {
        let provider = makeSignalingProvider(codexPath: "/fake/bin/codex")

        guard case .notInstalled = await provider.activitySignalStatus() else {
            return XCTFail("Expected notInstalled")
        }
        let setupBefore = await provider.currentSetupState()
        XCTAssertNil(setupBefore)

        try await provider.installActivitySignal()
        guard case .awaitingFirstSignal = await provider.activitySignalStatus() else {
            return XCTFail("Expected awaitingFirstSignal")
        }
        let setupAfter = await provider.currentSetupState()
        XCTAssertNil(setupAfter)

        try await provider.removeActivitySignal()
        guard case .notInstalled = await provider.activitySignalStatus() else {
            return XCTFail("Expected notInstalled after removal")
        }
    }

    // MARK: - Helpers

    private func makeSignalingProvider(codexPath: String?) -> OpenAICodexProvider {
        let locator = CodexLocator(
            environment: ["PATH": codexPath.map { ($0 as NSString).deletingLastPathComponent } ?? "", "HOME": "/test"],
            isExecutable: { $0 == codexPath }
        )
        return OpenAICodexProvider(
            locator: locator,
            client: CodexAppServerClient(timeout: 2, errorLog: makeErrorLog()),
            hooksInstaller: CodexHooksInstaller(
                hooksURL: temporaryDirectory.appendingPathComponent(".codex/hooks.json"),
                signalURL: signalURL
            )
        )
    }

    /// FSEvents only reports changes after the stream starts, so give it a
    /// moment before the test touches anything.
    private func startCounting(_ signals: AsyncStream<Date>) async -> (SignalCounter, Task<Void, Never>) {
        let counter = SignalCounter()
        let task = Task {
            for await _ in signals {
                await counter.increment()
            }
        }
        try? await Task.sleep(for: .milliseconds(300))
        return (counter, task)
    }

    private func touchSignalFile() throws {
        try FileManager.default.createDirectory(
            at: signalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        process.arguments = [signalURL.path]
        try process.run()
        process.waitUntilExit()
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while await !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
