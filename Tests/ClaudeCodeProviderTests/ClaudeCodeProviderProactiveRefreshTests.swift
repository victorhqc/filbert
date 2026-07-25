@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeProviderProactiveRefreshTests: XCTestCase {
    private var cacheURL: URL!
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-proactive-tests-\(UUID().uuidString)")
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

    // MARK: - registry downcast succeeds

    func testClaudeCodeProvider_conformsToProactiveRefreshable() {
        let provider = makeProvider()
        // Erase to `any AIProvider` so the compiler cannot statically prove
        // the conformance — the test is about runtime behaviour.
        let anyProvider: any AIProvider = provider
        XCTAssert(anyProvider is ProactiveRefreshable)
    }

    // MARK: - proactiveRefresh delegates to the refresher

    func testProactiveRefresh_delegatesToRefresher_andRecordsDebounce() async throws {
        // We can't stub the refresher actor directly, so point it at a fake
        // binary that records each spawn to a log file.
        let spawnLogURL = tmpDir.appendingPathComponent("spawn.log")
        let fakeBinaryURL = try writeFakeClaudeBinary(
            body: "#!/bin/bash\necho spawned >> \"\(spawnLogURL.path)\"\n"
        )
        let refresher = ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: fakeBinaryURL.path)
        )
        let provider = ClaudeCodeProvider(
            locator: ClaudeCodeLocator(injectedPath: fakeBinaryURL.path),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            installer: makeInstaller(helperInstalled: true),
            refresher: refresher
        )

        try await provider.proactiveRefresh()
        try await provider.proactiveRefresh()

        let spawnCount = readSpawnCount(at: spawnLogURL)
        XCTAssertEqual(spawnCount, 1, "Second call must be debounced by the refresher")
    }

    // MARK: - fetchQuota must NOT spawn `claude`

    func testFetchQuota_doesNotSpawn_whenCalledDirectly() async throws {
        let spawnLogURL = tmpDir.appendingPathComponent("spawn.log")
        let fakeBinaryURL = try writeFakeClaudeBinary(
            body: "#!/bin/bash\necho spawned >> \"\(spawnLogURL.path)\"\n"
        )
        let refresher = ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: fakeBinaryURL.path)
        )
        let provider = ClaudeCodeProvider(
            locator: ClaudeCodeLocator(injectedPath: fakeBinaryURL.path),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            installer: makeInstaller(helperInstalled: true),
            refresher: refresher
        )

        _ = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: ClaudeCodeProvider.baseURL
        )

        let spawnCount = readSpawnCount(at: spawnLogURL)
        XCTAssertEqual(spawnCount, 0, "fetchQuota must not spawn `claude` — only proactiveRefresh does")
    }

    // MARK: - Helpers

    private func makeProvider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            locator: ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude"),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            installer: makeInstaller(helperInstalled: true)
        )
    }

    private func makeInstaller(helperInstalled: Bool) -> StatuslineHelperInstaller {
        let helperURL: URL = if helperInstalled {
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

    private func writeFakeClaudeBinary(body: String) throws -> URL {
        let url = tmpDir.appendingPathComponent("fake-claude-\(UUID().uuidString)")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    private func readSpawnCount(at url: URL) -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.components(separatedBy: .newlines)
            .filter { $0 == "spawned" }
            .count
    }
}
