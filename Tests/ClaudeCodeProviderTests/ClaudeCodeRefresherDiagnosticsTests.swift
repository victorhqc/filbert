@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeRefresherDiagnosticsTests: XCTestCase {
    func testValidateUsageOutput_reportsEveryFailureReasonInOrder() {
        for testCase in Self.failureCases {
            let validation = ClaudeCodeRefresher.validateUsageOutput(testCase.data, truncated: testCase.truncated)
            XCTAssertEqual(validation.failure, testCase.expected, testCase.name)
            XCTAssertTrue(validation.windows.isEmpty, testCase.name)
        }
    }

    func testValidateUsageOutput_acceptsUsageWindows() {
        let data = usageData(session: 77, week: 37)
        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)
        XCTAssertNil(validation.failure)
        XCTAssertEqual(validation.windows.count, 2)
        XCTAssertEqual(validation.cliReportedError, false)
    }

    func testValidateUsageOutput_errorResponseWithMatchingUsageTextYieldsNoWindows() {
        let result = usageText(session: 77, week: 37)
        let data = Data(#"{"is_error":true,"result":"\#(result)"}"#.utf8)
        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)
        XCTAssertEqual(validation.failure, .cliReportedError)
        XCTAssertTrue(validation.windows.isEmpty)
        XCTAssertEqual(validation.cliReportedError, true)
    }

    func testValidateUsageOutput_decodesIsErrorStrictly() {
        let absent = ClaudeCodeRefresher.validateUsageOutput(
            Data(#"{"result":"banner"}"#.utf8), truncated: false
        )
        XCTAssertNil(absent.cliReportedError)

        let falseValue = ClaudeCodeRefresher.validateUsageOutput(
            Data(#"{"is_error":false,"result":"banner"}"#.utf8), truncated: false
        )
        XCTAssertEqual(falseValue.cliReportedError, false)

        let stringValue = ClaudeCodeRefresher.validateUsageOutput(
            Data(#"{"is_error":"true","result":"banner"}"#.utf8), truncated: false
        )
        XCTAssertNil(stringValue.cliReportedError)

        let numberValue = ClaudeCodeRefresher.validateUsageOutput(
            Data(#"{"is_error":1,"result":"banner"}"#.utf8), truncated: false
        )
        XCTAssertNil(numberValue.cliReportedError)
    }

    private static let failureCases: [FailureCase] = [
        FailureCase(
            name: "truncated beats everything",
            data: Data(#"{"result":"Current session: 5% used"}"#.utf8),
            truncated: true,
            expected: .outputTooLarge
        ),
        FailureCase(name: "no bytes", data: Data(), truncated: false, expected: .emptyOutput),
        FailureCase(name: "whitespace only", data: Data(" \t\n\r".utf8), truncated: false, expected: .emptyOutput),
        FailureCase(
            name: "not json",
            data: Data("Current session: 5% used".utf8),
            truncated: false,
            expected: .invalidJSON
        ),
        FailureCase(name: "array root", data: Data("[1,2,3]".utf8), truncated: false, expected: .invalidEnvelope),
        FailureCase(
            name: "string root",
            data: Data(#""just text""#.utf8),
            truncated: false,
            expected: .invalidEnvelope
        ),
        FailureCase(name: "null root", data: Data("null".utf8), truncated: false, expected: .invalidEnvelope),
        FailureCase(
            name: "cli reported error",
            data: Data(#"{"is_error":true,"result":"Current session: 5% used"}"#.utf8),
            truncated: false,
            expected: .cliReportedError
        ),
        FailureCase(
            name: "result missing",
            data: Data(#"{"type":"result"}"#.utf8),
            truncated: false,
            expected: .resultMissing
        ),
        FailureCase(
            name: "result null",
            data: Data(#"{"result":null}"#.utf8),
            truncated: false,
            expected: .resultInvalid
        ),
        FailureCase(
            name: "result not a string",
            data: Data(#"{"result":42}"#.utf8),
            truncated: false,
            expected: .resultInvalid
        ),
        FailureCase(
            name: "banner only",
            data: Data(#"{"is_error":false,"result":"Claude Pro plan. Manage at claude.ai"}"#.utf8),
            truncated: false,
            expected: .usageWindowsMissing
        ),
    ]

    private struct FailureCase {
        let name: String
        let data: Data
        let truncated: Bool
        let expected: OutputFailure
    }

    private func usageText(session: Int, week: Int) -> String {
        let line1 = "Current session: \(session)% used · resets Jul 21 at 12:59am (Europe/Berlin)"
        let line2 = "Current week (all models): \(week)% used · resets Jul 24 at 5:59am (Europe/Berlin)"
        return "\(line1)\\n\(line2)"
    }

    private func usageData(session: Int, week: Int) -> Data {
        let result = usageText(session: session, week: week)
        let json = #"{"type":"result","is_error":false,"result":"\#(result)"}"#
        return Data(json.utf8)
    }
}
