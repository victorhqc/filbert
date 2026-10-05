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

    func testValidateUsageOutput_readsStructuredReport() {
        let data = reportJSON(limits: [
            row(kind: "session", percent: "54", resetsAt: "2026-10-05T13:50:00.473061+00:00"),
            row(kind: "weekly_all", percent: "18", resetsAt: "2026-10-09T06:00:00.473081+00:00"),
        ].joined(separator: ","))

        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)

        XCTAssertNil(validation.failure)
        XCTAssertNil(validation.cliReportedError)
        XCTAssertEqual(validation.windows.map(\.slot), [.fiveHour, .sevenDay])
        XCTAssertEqual(validation.windows.first?.window.usedPercentage, 54)
        XCTAssertEqual(validation.windows.last?.window.usedPercentage, 18)
        XCTAssertNotNil(validation.windows.first?.window.resetsAt)
    }

    func testValidateUsageOutput_structuredTakesPrecedenceOverProse() {
        let prose = usageText(session: 5, week: 6)
        let report = usageReportValue(limits: row(kind: "session", percent: "54"))
        let data = Data(#"{"result":"\#(prose)","usage_report":\#(report)}"#.utf8)

        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)

        XCTAssertEqual(validation.windows.first { $0.slot == .fiveHour }?.window.usedPercentage, 54)
        XCTAssertEqual(validation.windows.first { $0.slot == .sevenDay }?.window.usedPercentage, 6)
    }

    func testValidateUsageOutput_ignoresInactiveScopedAndUnknownRows() {
        let data = reportJSON(limits: [
            row(kind: "weekly_scoped", percent: "20"),
            row(kind: "monthly", percent: "99"),
            row(kind: "weekly_all", percent: "18", isActive: "false"),
        ].joined(separator: ","))

        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)

        XCTAssertNil(validation.failure)
        XCTAssertEqual(validation.windows.count, 1)
        XCTAssertEqual(validation.windows.first?.slot, .sevenDay)
        XCTAssertEqual(validation.windows.first?.window.usedPercentage, 18)
    }

    func testValidateUsageOutput_malformedRowsDoNotDiscardValidRows() {
        let data = reportJSON(limits: [
            row(kind: "session", percent: "\"54\""),
            "\"not a row\"",
            row(kind: "session", percent: "60"),
        ].joined(separator: ","))

        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)

        XCTAssertEqual(validation.windows.count, 1)
        XCTAssertEqual(validation.windows.first?.window.usedPercentage, 60)
    }

    func testValidateUsageOutput_missingPercentYieldsNoWindow() {
        let data = reportJSON(limits: row(kind: "session", resetsAt: "2026-10-05T13:50:00+00:00"))

        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)

        XCTAssertEqual(validation.failure, .usageWindowsMissing)
        XCTAssertTrue(validation.windows.isEmpty)
    }

    func testValidateUsageOutput_invalidResetKeepsPercentage() {
        let data = reportJSON(limits: row(kind: "session", percent: "54", resetsAt: "not a date"))

        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)

        XCTAssertNil(validation.failure)
        XCTAssertEqual(validation.windows.first?.window.usedPercentage, 54)
        XCTAssertNil(validation.windows.first?.window.resetsAt)
    }

    func testValidateUsageOutput_errorObjectWithUsableStructuredDataStillFails() {
        let report = usageReportValue(limits: row(kind: "session", percent: "54"))
        let data = Data(#"{"is_error":true,"usage_report":\#(report)}"#.utf8)

        let validation = ClaudeCodeRefresher.validateUsageOutput(data, truncated: false)

        XCTAssertEqual(validation.failure, .cliReportedError)
        XCTAssertEqual(validation.cliReportedError, true)
        XCTAssertTrue(validation.windows.isEmpty)
    }

    func testParseISOTimestamp_acceptsFractionalAndPlainForms() throws {
        let plain = try XCTUnwrap(ClaudeCodeRefresher.parseISOTimestamp("2026-10-05T13:50:00+00:00"))
        let fractional = try XCTUnwrap(ClaudeCodeRefresher.parseISOTimestamp("2026-10-05T13:50:00.473061+00:00"))

        XCTAssertEqual(plain, 1_791_208_200, accuracy: 0.5)
        XCTAssertEqual(fractional, plain, accuracy: 1)
        XCTAssertGreaterThan(fractional, plain)
        XCTAssertNil(ClaudeCodeRefresher.parseISOTimestamp("not a date"))
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
        FailureCase(
            name: "usage report without usable rows",
            data: Data(#"{"usage_report":{"rate_limits":{"limits":[]}}}"#.utf8),
            truncated: false,
            expected: .usageWindowsMissing
        ),
        FailureCase(
            name: "usage report not an object",
            data: Data(#"{"usage_report":42}"#.utf8),
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

    private func reportJSON(limits: String) -> Data {
        Data(#"{"usage_report":\#(usageReportValue(limits: limits))}"#.utf8)
    }

    private func usageReportValue(limits: String) -> String {
        #"{"rate_limits":{"limits":[\#(limits)]}}"#
    }

    private func row(
        kind: String,
        percent: String? = nil,
        resetsAt: String? = nil,
        isActive: String? = nil
    ) -> String {
        var fields = ["\"kind\":\"\(kind)\""]
        if let percent {
            fields.append("\"percent\":\(percent)")
        }
        if let resetsAt {
            fields.append("\"resets_at\":\"\(resetsAt)\"")
        }
        if let isActive {
            fields.append("\"is_active\":\(isActive)")
        }
        return "{\(fields.joined(separator: ","))}"
    }

    private func usageData(session: Int, week: Int) -> Data {
        let result = usageText(session: session, week: week)
        let json = #"{"type":"result","is_error":false,"result":"\#(result)"}"#
        return Data(json.utf8)
    }
}
