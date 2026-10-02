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
