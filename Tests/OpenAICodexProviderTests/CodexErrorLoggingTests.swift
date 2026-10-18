import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

extension OpenAICodexProviderTests {
    func testClientRecordsSkippedMalformedEnvelopeWithoutSubprocessOutput() async throws {
        let executable = try writeServer(
            name: "codex-malformed-envelope",
            body: serverBody(
                response: """
                printf '%s\\n' 'subprocess-secret'
                printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":null}}'
                """
            )
        )
        let errorLog = makeErrorLog()

        _ = try await CodexAppServerClient(timeout: 2, errorLog: errorLog)
            .readRateLimits(at: executable.path)

        let logURL = try XCTUnwrap(errorLog.availableFileURL)
        let records = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(records.split(whereSeparator: \.isNewline).count, 1)
        XCTAssertTrue(records.contains("response_decoding_failed"))
        XCTAssertTrue(records.contains("openai-codex"))
        XCTAssertFalse(records.contains("subprocess-secret"))
    }

    func testClientDrainsStderrLargerThanThePipeBuffer() async throws {
        let rateLimitResult = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":"
            + "{\"rateLimits\":{\"primary\":{\"usedPercent\":12,\"windowDurationMins\":300}}}}"
        let executable = try writeServer(
            name: "codex-noisy-stderr",
            body: """
            head -c 262144 /dev/zero >&2
            \(serverBody(response: "printf '%s\\n' '\(rateLimitResult)'"))
            """
        )

        let result = try await CodexAppServerClient(timeout: 2, errorLog: makeErrorLog())
            .readRateLimits(at: executable.path)

        XCTAssertEqual(result.rateLimits?.primary?.usedPercent, 12)
    }

    func testChildExitRecordsCauseCodeExitStatusAndStderrSizeOnly() async throws {
        let executable = try writeServer(
            name: "codex-exits",
            body: """
            read _
            printf '%s' 'stderr-secret' >&2
            exit 3
            """
        )

        let failure = try await clientFailure(executable: executable, timeout: 2)

        XCTAssertEqual(failure.reason, .childExited)
        XCTAssertEqual(failure.diagnosticCode, "child-exited")
        XCTAssertEqual(failure.subprocess?.exitStatus, 3)
        XCTAssertEqual(failure.subprocess?.stderrBytes, 13)

        let errorLog = makeErrorLog()
        errorLog.record(
            component: "app", operation: "fetch-quota", code: "operation-failed",
            providerID: OpenAICodexProvider.providerId, error: failure
        )
        let records = try String(contentsOf: XCTUnwrap(errorLog.availableFileURL), encoding: .utf8)
        XCTAssertTrue(records.contains("\"causeCode\":\"child-exited\""))
        XCTAssertTrue(records.contains("\"exitStatus\":3"))
        XCTAssertTrue(records.contains("\"stderrBytes\":13"))
        XCTAssertFalse(records.contains("stderr-secret"))
    }

    func testTimeoutRecordsTheTimedOutCauseCode() async throws {
        let executable = try writeServer(
            name: "codex-silent",
            body: """
            read _
            sleep 60
            """
        )

        let failure = try await clientFailure(executable: executable, timeout: 0.2)

        XCTAssertEqual(failure.reason, .timedOut)
        XCTAssertEqual(failure.diagnosticCode, "timed-out")
        XCTAssertNotNil(failure.subprocess?.exitStatus)
    }

    func testLaunchFailureAndMissingBinaryHaveCauseCodes() async throws {
        let notExecutable = temporaryDirectory.appendingPathComponent("not-codex")
        try Data().write(to: notExecutable)

        let failure = try await clientFailure(executable: notExecutable, timeout: 2)

        XCTAssertEqual(failure.diagnosticCode, "launch-failed")
        XCTAssertNil(failure.subprocess)
        XCTAssertEqual(OpenAICodexError.binaryNotFound.diagnosticCode, "binary-not-found")
    }

    private func clientFailure(executable: URL, timeout: TimeInterval) async throws -> CodexAppServerFailure {
        var failure: CodexAppServerFailure?
        do {
            _ = try await CodexAppServerClient(timeout: timeout, errorLog: makeErrorLog())
                .readRateLimits(at: executable.path)
        } catch let error as CodexAppServerFailure {
            failure = error
        }
        return try XCTUnwrap(failure, "Expected a Codex app-server failure")
    }

    func serverBody(response: String) -> String {
        """
        read _
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        read _
        read _
        \(response)
        """
    }
}
