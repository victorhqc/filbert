@testable import Core
import Foundation
import XCTest

final class ErrorLogSubprocessDiagnosticsTests: XCTestCase {
    func testOmitsAbsentSubprocessFieldsAndKeepsTypedValues() throws {
        let log = try ErrorLog(directoryURL: temporaryDirectory())
        XCTAssertTrue(log.record(
            component: "provider", operation: "proactive-refresh", code: "operation-failed",
            error: MinimalFailure()
        ))
        let record = try XCTUnwrap(records(at: log.fileURL).first)
        XCTAssertEqual(record["causeCode"] as? String, "usage-data-missing")
        XCTAssertEqual(record["exitStatus"] as? Int, 0)
        XCTAssertEqual(record["stdoutTruncated"] as? Bool, false)
        XCTAssertNil(record["cliReportedError"])
        XCTAssertNil(record["outputFailure"])
        XCTAssertNil(record["stdoutJSONShape"])
    }

    func testRecordsEveryRootShapeValue() throws {
        let log = try ErrorLog(directoryURL: temporaryDirectory())
        for shape in JSONRootShape.allCases {
            XCTAssertTrue(log.record(
                component: "app", operation: "proactive-refresh", code: "operation-failed",
                error: ShapedFailure(shape: shape)
            ))
        }
        let shapes = try records(at: log.fileURL).map { $0["stdoutJSONShape"] as? String }
        XCTAssertEqual(shapes, ["object", "array", "scalar", "null"])
    }

    func testOmitsSubprocessFieldsForErrorsWithoutMetadata() throws {
        let log = try ErrorLog(directoryURL: temporaryDirectory())
        XCTAssertTrue(log.record(
            component: "core", operation: "resolve-enablement", code: "credential-read-failed",
            error: NSError(domain: NSOSStatusErrorDomain, code: -25300)
        ))
        let record = try XCTUnwrap(records(at: log.fileURL).first)
        XCTAssertNil(record["causeCode"])
        XCTAssertNil(record["exitStatus"])
        XCTAssertNil(record["stdoutBytes"])
        XCTAssertNil(record["stderrBytes"])
        XCTAssertNil(record["stdoutTruncated"])
        XCTAssertNil(record["cliReportedError"])
        XCTAssertNil(record["outputFailure"])
        XCTAssertNil(record["stdoutJSONShape"])
    }

    private struct ShapedFailure: DiagnosticError {
        let diagnosticCode = "usage-data-missing"
        let shape: JSONRootShape
        var diagnosticSubprocess: SubprocessDiagnostic? {
            SubprocessDiagnostic(
                exitStatus: 0,
                stdoutBytes: 9017,
                stderrBytes: 0,
                stdoutTruncated: false,
                outputFailure: .invalidEnvelope,
                stdoutJSONShape: shape
            )
        }
    }

    private struct MinimalFailure: DiagnosticError {
        let diagnosticCode = "usage-data-missing"
        var diagnosticSubprocess: SubprocessDiagnostic? {
            SubprocessDiagnostic(
                exitStatus: 0,
                stdoutBytes: 0,
                stderrBytes: 0,
                stdoutTruncated: false
            )
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorLogSubprocessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func records(at url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }
}
