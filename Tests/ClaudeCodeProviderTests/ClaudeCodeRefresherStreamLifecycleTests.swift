@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeRefresherStreamLifecycleTests: XCTestCase {
    private var tmpDir: URL!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-refresher-stream-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
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

    func testRefresh_isBoundedWhenDescendantKeepsWriting() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-flooding-descendant",
            body: """
            #!/bin/bash
            ( yes A ) &
            cat <<'JSON'
            {"is_error":false,"result":"\(usageText(session: 12, week: 34))"}
            JSON
            exit 0
            """
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        let start = Date()
        let error = try await capturedError(from: refresher)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 5, "a continuously writing descendant must not extend finalization")
        guard case let .noUsageData(diagnostic) = error else {
            return XCTFail("Expected noUsageData, got \(error)")
        }
        XCTAssertTrue(diagnostic.stdoutTruncated)
        XCTAssertEqual(diagnostic.outputFailure, .outputTooLarge)
    }

    func testRefresh_handlesClosedStdoutWhileChildStaysAlive() async throws {
        let fakeBinary = try writeFakeBinary(
            name: "fake-claude-closed-stdout",
            body: """
            #!/bin/bash
            exec 1>&-
            printf '%s' 'stderr-while-alive' 1>&2
            sleep 1
            exit 0
            """
        )
        let refresher = makeRefresher(binaryPath: fakeBinary.path)

        let start = Date()
        let error = try await capturedError(from: refresher)
        let elapsed = Date().timeIntervalSince(start)

        guard case let .noUsageData(diagnostic) = error else {
            return XCTFail("Expected noUsageData, got \(error)")
        }
        XCTAssertEqual(diagnostic.outputFailure, .emptyOutput)
        XCTAssertEqual(diagnostic.stderrBytes, "stderr-while-alive".utf8.count)
        XCTAssertLessThan(elapsed, 5)
    }

    private func makeRefresher(binaryPath: String) -> ClaudeCodeRefresher {
        ClaudeCodeRefresher(
            locator: ClaudeCodeLocator(injectedPath: binaryPath),
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            spawnTimeout: 30,
            terminateGrace: 2,
            spawnDebounce: 60
        )
    }

    private func capturedError(from refresher: ClaudeCodeRefresher) async throws -> ClaudeCodeRefresherError {
        do {
            try await refresher.refresh()
        } catch let error as ClaudeCodeRefresherError {
            return error
        }
        XCTFail("Expected the refresh to fail")
        struct UnexpectedSuccess: Error {}
        throw UnexpectedSuccess()
    }

    private func usageText(session: Int, week: Int) -> String {
        let line1 = "Current session: \(session)% used · resets Jul 21 at 12:59am (Europe/Berlin)"
        let line2 = "Current week (all models): \(week)% used · resets Jul 24 at 5:59am (Europe/Berlin)"
        return "\(line1)\\n\(line2)"
    }

    private func writeFakeBinary(name: String, body: String) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }
}
