import Core
import Foundation
import XCTest

final class ErrorLogContextTests: XCTestCase {
    func testWrappedURLErrorRecordsItsCodeWithoutPrivateContent() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory)
        let secret = "SECRET_TOKEN_IN_URL"
        let failingURL = try XCTUnwrap(URL(string: "https://api.example.com/balance?key=\(secret)"))
        let urlError = URLError(
            .timedOut,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL, NSLocalizedDescriptionKey: secret]
        )

        XCTAssertTrue(log.record(
            component: "app", operation: "fetch-quota", code: "operation-failed",
            providerID: "deepseek",
            error: WrappedTransportError(underlyingError: urlError),
            context: ErrorLogContext(trigger: .wake, networkPath: .unsatisfied)
        ))

        let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertFalse(contents.contains(secret))
        XCTAssertFalse(contents.contains("api.example.com"))
        let record = try XCTUnwrap(records(at: log.fileURL).first)
        XCTAssertEqual(record["errorDomain"] as? String, NSURLErrorDomain)
        XCTAssertEqual(record["errorCode"] as? Int, URLError.timedOut.rawValue)
        XCTAssertEqual(record["trigger"] as? String, "wake")
        XCTAssertEqual(record["networkPath"] as? String, "unsatisfied")
    }

    func testRecordsWithoutContextOmitContextFields() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory)

        XCTAssertTrue(log.record(component: "app", operation: "save-key", code: "operation-failed"))

        let record = try XCTUnwrap(records(at: log.fileURL).first)
        XCTAssertNil(record["trigger"])
        XCTAssertNil(record["networkPath"])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorLogContextTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func records(at url: URL) throws -> [[String: Any]] {
        try Data(contentsOf: url).split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }
}

private struct WrappedTransportError: UnderlyingErrorProviding {
    let underlyingError: (any Error)?
}
