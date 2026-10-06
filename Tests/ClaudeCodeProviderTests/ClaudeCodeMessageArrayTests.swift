@testable import ClaudeCodeProvider
import Core
import XCTest

final class ClaudeCodeMessageArrayTests: XCTestCase {
    private typealias Messages = SyntheticClaudeMessages

    func testSuppliedReportAsObjectRoot_selectsSessionAndAllModelsWeek() throws {
        let object: [String: Any] = [
            "usage_report": Messages.suppliedReport(),
            "claude_code_version": "2.1.280",
            "model": "claude-opus-5-5[1m]",
        ]

        let validation = try validate(object)

        XCTAssertNil(validation.failure)
        XCTAssertEqual(validation.rootShape, .object)
        XCTAssertEqual(percent(validation, .fiveHour), 54)
        XCTAssertEqual(percent(validation, .sevenDay), 18)
    }

    func testSuppliedReportOnSyntheticInitMessage_fillsWindowsTheResultLacks() throws {
        let validation = try validate([
            Messages.initMessage(report: Messages.suppliedReport()),
            Messages.result(text: "Claude Pro plan. Manage at claude.ai"),
        ])

        XCTAssertNil(validation.failure)
        XCTAssertEqual(validation.rootShape, .array)
        XCTAssertEqual(validation.cliReportedError, false)
        XCTAssertEqual(percent(validation, .fiveHour), 54)
        XCTAssertEqual(percent(validation, .sevenDay), 18)
    }

    func testSuppliedReportOnSyntheticResultMessage_selectsItsWindows() throws {
        let validation = try validate([
            Messages.initMessage(),
            Messages.result(text: "", report: Messages.suppliedReport()),
        ])

        XCTAssertNil(validation.failure)
        XCTAssertEqual(percent(validation, .fiveHour), 54)
        XCTAssertEqual(percent(validation, .sevenDay), 18)
    }

    func testDocumentedMessageOrder_readsProseFromTheResultMessage() throws {
        let validation = try validate([
            Messages.initMessage(),
            Messages.rateLimitEvent(),
            Messages.assistant(text: Messages.usageText(session: 99, week: 99)),
            Messages.result(text: Messages.usageText(session: 12, week: 34)),
        ])

        XCTAssertNil(validation.failure)
        XCTAssertEqual(percent(validation, .fiveHour), 12)
        XCTAssertEqual(percent(validation, .sevenDay), 34)
    }

    func testUsageTextOnlyInAssistantContent_fails() throws {
        let withResult = try validate([
            Messages.initMessage(),
            Messages.assistant(text: Messages.usageText(session: 12, week: 34)),
            Messages.result(text: ""),
        ])
        XCTAssertEqual(withResult.failure, .usageWindowsMissing)
        XCTAssertTrue(withResult.windows.isEmpty)

        let withoutResult = try validate([
            Messages.initMessage(),
            Messages.assistant(text: Messages.usageText(session: 12, week: 34)),
        ])
        XCTAssertEqual(withoutResult.failure, .resultMissing)
        XCTAssertTrue(withoutResult.windows.isEmpty)
    }

    func testArrayWithoutResultMessage_failsEvenWithUsableInitReport() throws {
        let validation = try validate([Messages.initMessage(report: Messages.report(session: 54, week: 18))])

        XCTAssertEqual(validation.failure, .resultMissing)
        XCTAssertEqual(validation.rootShape, .array)
        XCTAssertNil(validation.cliReportedError)
        XCTAssertTrue(validation.windows.isEmpty)
    }

    func testMaxTurnsResultWithoutResultText_fails() throws {
        var maxTurns = Messages.result(isError: true)
        maxTurns["subtype"] = "error_max_turns"
        maxTurns["errors"] = ["Reached maximum number of turns"]
        let flagged = try validate([Messages.initMessage(report: Messages.report(session: 54)), maxTurns])
        XCTAssertEqual(flagged.failure, .cliReportedError)
        XCTAssertEqual(flagged.cliReportedError, true)

        maxTurns["is_error"] = nil
        let unflagged = try validate([Messages.initMessage(), maxTurns])
        XCTAssertEqual(unflagged.failure, .resultMissing)
        XCTAssertNil(unflagged.cliReportedError)
    }

    func testTwoResultMessages_lastProseWinsAndEitherErrorFails() throws {
        let first = Messages.result(text: Messages.usageText(session: 12, week: 34))
        let second = Messages.result(text: Messages.usageText(session: 56, week: 78))
        let both = try validate([first, second])
        XCTAssertEqual(percent(both, .fiveHour), 56)
        XCTAssertEqual(percent(both, .sevenDay), 78)

        let failed = Messages.result(text: Messages.usageText(session: 1, week: 2), isError: true)
        for messages in [[failed, second], [second, failed]] {
            let validation = try validate(messages)
            XCTAssertEqual(validation.failure, .cliReportedError)
            XCTAssertEqual(validation.cliReportedError, true)
            XCTAssertTrue(validation.windows.isEmpty)
        }
    }

    func testSourceRanks_resultReportThenResultProseThenOtherReports() throws {
        let initReport = Messages.initMessage(report: Messages.report(session: 90, week: 91))
        let result = Messages.result(
            text: Messages.usageText(session: 12, week: 34),
            report: Messages.report(session: 54)
        )
        for messages in [[initReport, result], [result, initReport]] {
            let validation = try validate(messages)
            XCTAssertEqual(percent(validation, .fiveHour), 54)
            XCTAssertEqual(percent(validation, .sevenDay), 34)
        }

        let sessionOnly = Messages.result(text: Messages.usageText(session: 12, week: nil))
        for messages in [[initReport, sessionOnly], [sessionOnly, initReport]] {
            let validation = try validate(messages)
            XCTAssertEqual(percent(validation, .fiveHour), 12)
            XCTAssertEqual(percent(validation, .sevenDay), 91)
        }
    }

    func testRepeatedReports_lastValidRowInArrayOrderWins() throws {
        let validation = try validate([
            Messages.initMessage(report: Messages.report(session: 10, week: 20)),
            Messages.initMessage(report: Messages.report(session: 11)),
            Messages.result(text: "", report: Messages.report(session: 54)),
            Messages.result(text: "", report: Messages.report(session: "99")),
        ])

        XCTAssertEqual(percent(validation, .fiveHour), 54)
        XCTAssertEqual(percent(validation, .sevenDay), 20)
    }

    func testResultAndErrorFieldsOutsideResultMessagesAreIgnored() throws {
        let usage = Messages.usageText(session: 99, week: 99)
        let validation = try validate([
            ["type": "system", "subtype": "init", "is_error": true, "result": usage],
            ["is_error": true, "result": usage],
            ["type": "mystery", "is_error": true, "result": usage],
            ["type": 5, "is_error": true, "result": usage],
            ["type": "assistant", "is_error": true, "result": usage],
            Messages.result(text: Messages.usageText(session: 12, week: 34), isError: nil),
        ])

        XCTAssertNil(validation.failure)
        XCTAssertNil(validation.cliReportedError)
        XCTAssertEqual(percent(validation, .fiveHour), 12)
        XCTAssertEqual(percent(validation, .sevenDay), 34)
    }

    func testNestedToolErrorsAndNonBooleanFlagsAreNotCLIErrors() throws {
        let usage = Messages.usageText(session: 12, week: 34)
        let nested = try validate([Messages.toolResultError(), Messages.result(text: usage)])
        XCTAssertNil(nested.failure)
        XCTAssertEqual(nested.cliReportedError, false)

        let stringFlag = try validate([Messages.result(text: usage, isError: "true")])
        XCTAssertNil(stringFlag.failure)
        XCTAssertNil(stringFlag.cliReportedError)
    }

    func testAggregateCLIReportedError() throws {
        let banner = "Claude Pro plan. Manage at claude.ai"
        let falseAndAbsent = try validate([
            Messages.result(text: banner, isError: false),
            Messages.result(text: banner, isError: nil),
        ])
        XCTAssertEqual(falseAndAbsent.cliReportedError, false)

        let absent = try validate([Messages.result(text: banner, isError: nil)])
        XCTAssertNil(absent.cliReportedError)
    }

    func testFailureClassificationOrder() throws {
        let cases: KeyValuePairs<String, (value: Any, expected: OutputFailure)> = [
            "empty array": ([Any](), .invalidEnvelope),
            "non-object element": ([Messages.result(text: "x", isError: true), 1], .invalidEnvelope),
            "nested array": ([[Messages.result(text: "x")]], .invalidEnvelope),
            "no result element": ([Messages.initMessage()], .resultMissing),
            "error before windows": ([Messages.result(text: "x", isError: true)], .cliReportedError),
            "report anywhere": (
                [Messages.initMessage(report: Messages.report(rows: [])), Messages.result(text: 42)],
                .usageWindowsMissing
            ),
            "report not an object": ([Messages.initMessage(report: 42), Messages.result()], .usageWindowsMissing),
            "string result": ([Messages.result(text: "banner")], .usageWindowsMissing),
            "non-string result": ([Messages.result(text: 42)], .resultInvalid),
            "null result": ([Messages.result(text: NSNull())], .resultInvalid),
            "result field absent": ([Messages.result()], .resultMissing),
        ]
        for (name, testCase) in cases {
            let validation = try validate(testCase.value)
            XCTAssertEqual(validation.failure, testCase.expected, name)
            XCTAssertEqual(validation.rootShape, .array, name)
            XCTAssertTrue(validation.windows.isEmpty, name)
        }
    }

    func testRootShapeComesFromTheSameDecodingPass() throws {
        let decoded: KeyValuePairs<String, (value: Any, expected: JSONRootShape)> = [
            "object": (["result": "banner"], .object),
            "array": ([Messages.result(text: "banner")], .array),
            "string": ("just text", .scalar),
            "number": (42, .scalar),
            "boolean": (true, .scalar),
            "null": (NSNull(), .null),
        ]
        for (name, testCase) in decoded {
            XCTAssertEqual(try validate(testCase.value).rootShape, testCase.expected, name)
        }

        let undecoded: KeyValuePairs<String, (data: Data, expected: OutputFailure)> = [
            "not json": (Data("Current session: 5% used".utf8), .invalidJSON),
            "newline-separated objects": (Data("{\"result\":\"a\"}\n{\"result\":\"b\"}".utf8), .invalidJSON),
            "empty": (Data(), .emptyOutput),
            "nesting deeper than the decoder allows": (deeplyNestedObject(depth: 600), .invalidJSON),
        ]
        for (name, testCase) in undecoded {
            let validation = ClaudeCodeRefresher.validateUsageOutput(testCase.data, truncated: false)
            XCTAssertEqual(validation.failure, testCase.expected, name)
            XCTAssertNil(validation.rootShape, name)
        }

        let truncated = ClaudeCodeRefresher.validateUsageOutput(Data("[{\"type\":\"result\"}]".utf8), truncated: true)
        XCTAssertEqual(truncated.failure, .outputTooLarge)
        XCTAssertNil(truncated.rootShape)
    }

    private func validate(_ value: Any) throws -> ClaudeCodeRefresher.UsageOutputValidation {
        try ClaudeCodeRefresher.validateUsageOutput(Messages.data(value), truncated: false)
    }

    private func percent(
        _ validation: ClaudeCodeRefresher.UsageOutputValidation,
        _ slot: ClaudeCodeRefresher.WindowSlot
    ) -> Double? {
        validation.windows.first { $0.slot == slot }?.window.usedPercentage
    }

    private func deeplyNestedObject(depth: Int) -> Data {
        Data((String(repeating: #"{"a":"#, count: depth) + "1" + String(repeating: "}", count: depth)).utf8)
    }
}
