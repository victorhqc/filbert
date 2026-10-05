@testable import Core
import Darwin
import Foundation
import XCTest

final class ErrorLogTests: XCTestCase {
    func testWritesApprovedFieldsAndPrivatePermissions() throws {
        let directory = try temporaryDirectory().appendingPathComponent("logs")
        let log = ErrorLog(directoryURL: directory)
        XCTAssertNil(log.availableFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        XCTAssertTrue(log.record(
            component: "provider",
            operation: "fetch",
            code: "network_failure",
            providerID: "claude-code",
            error: NSError(domain: NSURLErrorDomain, code: -1009)
        ))

        let record = try XCTUnwrap(records(at: log.fileURL).first)
        XCTAssertEqual(record["component"] as? String, "provider")
        XCTAssertEqual(record["operation"] as? String, "fetch")
        XCTAssertEqual(record["code"] as? String, "network_failure")
        XCTAssertEqual(record["providerID"] as? String, "claude-code")
        XCTAssertEqual(record["errorDomain"] as? String, NSURLErrorDomain)
        XCTAssertEqual(record["errorCode"] as? Int, -1009)
        let timestamp = try XCTUnwrap(record["timestamp"] as? String)
        XCTAssertTrue(timestamp.hasSuffix("Z"))
        XCTAssertNotNil(ISO8601DateFormatter().date(from: timestamp))
        XCTAssertEqual(log.availableFileURL, log.fileURL)
        XCTAssertEqual(try permissions(at: directory), 0o700)
        XCTAssertEqual(try permissions(at: log.fileURL), 0o600)
        XCTAssertEqual(try permissions(at: directory.appendingPathComponent("errors.lock")), 0o600)
        XCTAssertEqual(
            ErrorLog.shared.fileURL,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Filbert/errors.log")
        )
    }

    func testDiscardsPrivateNSErrorAndDecodingContent() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory)
        let secret = "SECRET_API_TOKEN_AND_RESPONSE_BODY"
        let userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: secret,
            NSDebugDescriptionErrorKey: secret,
            NSUnderlyingErrorKey: NSError(domain: secret, code: 999),
            "response": secret,
        ]
        XCTAssertTrue(log.record(
            component: "provider", operation: "fetch", code: "failed",
            error: NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: userInfo)
        ))
        XCTAssertTrue(log.record(
            component: "provider", operation: "fetch", code: "failed",
            error: NSError(domain: secret, code: 123, userInfo: userInfo)
        ))
        let key = SecretCodingKey(stringValue: secret)
        let context = DecodingError.Context(
            codingPath: [key],
            debugDescription: secret,
            underlyingError: NSError(domain: secret, code: 456, userInfo: userInfo)
        )
        let errors: [DecodingError] = [
            .dataCorrupted(context),
            .keyNotFound(key, context),
            .typeMismatch(String.self, context),
            .valueNotFound(String.self, context),
        ]
        for error in errors {
            XCTAssertTrue(log.record(component: "cache", operation: "decode", code: "invalid", error: error))
        }

        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains(secret))
        let entries = try records(at: log.fileURL)
        XCTAssertEqual(entries[0]["errorCode"] as? Int, 260)
        XCTAssertNil(entries[1]["errorDomain"])
        XCTAssertNil(entries[1]["errorCode"])
        XCTAssertEqual(
            entries.dropFirst(2).compactMap { $0["decodingFailure"] as? String },
            ["dataCorrupted", "keyNotFound", "typeMismatch", "valueNotFound"]
        )
    }

    func testPreservesKeychainOSStatusWithoutNSErrorBridgeOrdinals() throws {
        let log = try ErrorLog(directoryURL: temporaryDirectory())
        let errors: [KeychainError] = [.saveFailed(-25293), .loadFailed(-25300), .deleteFailed(-50)]
        for error in errors {
            XCTAssertTrue(log.record(component: "keychain", operation: "access", code: "failed", error: error))
        }
        let entries = try records(at: log.fileURL)
        XCTAssertEqual(entries.compactMap { $0["errorCode"] as? Int }, [-25293, -25300, -50])
        XCTAssertEqual(entries.compactMap { $0["errorDomain"] as? String }, Array(
            repeating: NSOSStatusErrorDomain,
            count: 3
        ))
    }

    func testRotationRetainsOnlyTwoBoundedCompleteFiles() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory, maximumFileSize: 512)
        for index in 0 ..< 60 {
            XCTAssertTrue(log.record(component: "test", operation: "write", code: "failure_\(index)"))
        }
        let previous = directory.appendingPathComponent("errors.log.1")
        for file in [log.fileURL, previous] {
            XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 512)
            XCTAssertFalse(try records(at: file).isEmpty)
            XCTAssertEqual(try permissions(at: file), 0o600)
        }
        XCTAssertEqual(try records(at: log.fileURL).last?["code"] as? String, "failure_59")
        XCTAssertEqual(
            try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)),
            ["errors.log", "errors.log.1", "errors.lock"]
        )
    }

    func testHugeInputsStayBoundedWithoutBreakingJSONOrRecordLines() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory, maximumFileSize: 4096)
        let enormous = String(repeating: "👩🏽‍💻\n\u{0}\"\\", count: 100_000)
        for _ in 0 ..< 10 {
            XCTAssertTrue(log.record(
                component: enormous,
                operation: enormous,
                code: enormous,
                providerID: enormous
            ))
        }
        for file in [log.fileURL, directory.appendingPathComponent("errors.log.1")] {
            XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 4096)
            for record in try records(at: file) {
                for key in ["component", "operation", "code", "providerID"] {
                    let value = try XCTUnwrap(record[key] as? String)
                    XCTAssertLessThanOrEqual(value.utf8.count, 131)
                }
            }
        }
        let tiny = ErrorLog(directoryURL: directory.appendingPathComponent("tiny"), maximumFileSize: 1)
        XCTAssertFalse(tiny.record(component: "test", operation: "write", code: "failed"))
        XCTAssertNil(tiny.availableFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tiny.fileURL.path))
        let negative = ErrorLog(directoryURL: directory, maximumFileSize: -1)
        XCTAssertFalse(negative.record(component: "test", operation: "write", code: "failed"))
    }

    func testConcurrentInstancesAppendEveryCompleteRecord() async throws {
        let directory = try temporaryDirectory()
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for index in 0 ..< 200 {
                group.addTask {
                    ErrorLog(directoryURL: directory).record(
                        component: "test", operation: "write", code: "failure_\(index)"
                    )
                }
            }
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        XCTAssertEqual(results.count, 200)
        XCTAssertTrue(results.allSatisfy { $0 })
        let entries = try records(at: ErrorLog(directoryURL: directory).fileURL)
        XCTAssertEqual(entries.count, 200)
        XCTAssertEqual(Set(entries.compactMap { $0["code"] as? String }).count, 200)
    }

    func testConcurrentRotationKeepsCompleteBoundedRecords() async throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory, maximumFileSize: 512)
        let successes = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for index in 0 ..< 100 {
                group.addTask {
                    ErrorLog(directoryURL: directory, maximumFileSize: 512).record(
                        component: "test", operation: "write", code: "failure_\(index)"
                    )
                }
            }
            var success = true
            for await result in group {
                success = success && result
            }
            return success
        }
        XCTAssertTrue(successes)
        for file in [log.fileURL, directory.appendingPathComponent("errors.log.1")] {
            XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 512)
            XCTAssertFalse(try records(at: file).isEmpty)
        }
    }

    func testProcessesShareLockForAppendAndRotation() throws {
        let root = try temporaryDirectory()
        let executable = try compileWriter(in: root)
        for limit in [1_048_576, 512] {
            let directory = root.appendingPathComponent("logs-\(limit)")
            var processes: [Process] = []
            for index in 0 ..< 4 {
                let process = Process()
                process.executableURL = executable
                process.arguments = [directory.path, String(limit), String(index)]
                try process.run()
                processes.append(process)
            }
            for process in processes {
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0)
            }
            let log = ErrorLog(directoryURL: directory, maximumFileSize: limit)
            let entries = try records(at: log.fileURL)
            if limit == 1_048_576 {
                XCTAssertEqual(entries.count, 200)
                XCTAssertEqual(Set(entries.compactMap { $0["code"] as? String }).count, 200)
            } else {
                for file in [log.fileURL, directory.appendingPathComponent("errors.log.1")] {
                    XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, limit)
                    XCTAssertFalse(try records(at: file).isEmpty)
                }
            }
        }
    }
}

extension ErrorLogTests {
    func testPreservesSafeTypedCauseAndExitStatusWithoutErrorDescription() throws {
        let log = try ErrorLog(directoryURL: temporaryDirectory())
        XCTAssertTrue(log.record(
            component: "app", operation: "refresh", code: "failed",
            error: SafeDiagnosticFailure()
        ))
        let record = try XCTUnwrap(records(at: log.fileURL).first)
        XCTAssertEqual(record["causeCode"] as? String, "process-exited")
        XCTAssertEqual(record["exitStatus"] as? Int, 17)
        XCTAssertEqual(record["stdoutBytes"] as? Int, 2048)
        XCTAssertEqual(record["stderrBytes"] as? Int, 96)
        XCTAssertEqual(record["stdoutTruncated"] as? Bool, true)
        XCTAssertEqual(record["cliReportedError"] as? Bool, false)
        XCTAssertEqual(record["outputFailure"] as? String, "usage-windows-missing")
        XCTAssertFalse(try String(contentsOf: log.fileURL, encoding: .utf8).contains("SECRET"))
    }

    func testUnavailableWhenExistingLogCannotAcceptNewRecords() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory)
        XCTAssertTrue(log.record(component: "test", operation: "write", code: "failed"))
        XCTAssertEqual(chmod(log.fileURL.path, 0o400), 0)
        XCTAssertNil(log.availableFileURL)
        XCTAssertEqual(chmod(log.fileURL.path, 0o600), 0)
        XCTAssertEqual(chmod(directory.path, 0o500), 0)
        defer { chmod(directory.path, 0o700) }
        XCTAssertNil(log.availableFileURL)
    }

    func testInjectedLimitCannotExceedOneMiB() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory, maximumFileSize: .max)
        try Data(repeating: 0x41, count: 1_048_577).write(to: log.fileURL)

        XCTAssertNil(log.availableFileURL)
        XCTAssertTrue(log.record(component: "test", operation: "write", code: "failed"))
        XCTAssertEqual(try records(at: log.fileURL).count, 1)
        XCTAssertLessThanOrEqual(try Data(contentsOf: log.fileURL).count, 1_048_576)
        XCTAssertEqual(log.availableFileURL, log.fileURL)
    }

    func testInvalidLocationsAndUnsafeFilesFailWithoutChangingTargets() throws {
        let root = try temporaryDirectory()
        let ordinaryFile = root.appendingPathComponent("not-a-directory")
        let original = Data("KEEP_PRIVATE".utf8)
        try original.write(to: ordinaryFile)
        let invalid = ErrorLog(directoryURL: ordinaryFile)
        XCTAssertFalse(invalid.record(component: "test", operation: "write", code: "failed"))
        XCTAssertNil(invalid.availableFileURL)
        XCTAssertEqual(try Data(contentsOf: ordinaryFile), original)

        for name in ["errors.log", "errors.lock", "errors.log.1"] {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent(name),
                withDestinationURL: ordinaryFile
            )
            let log = ErrorLog(directoryURL: directory)
            XCTAssertFalse(log.record(component: "test", operation: "write", code: "failed"))
            XCTAssertNil(log.availableFileURL)
            XCTAssertEqual(try Data(contentsOf: ordinaryFile), original)
        }

        let unreadableRoot = root.appendingPathComponent("unwritable")
        try FileManager.default.createDirectory(at: unreadableRoot, withIntermediateDirectories: true)
        XCTAssertEqual(chmod(unreadableRoot.path, 0o500), 0)
        defer { chmod(unreadableRoot.path, 0o700) }
        let unwritable = ErrorLog(directoryURL: unreadableRoot.appendingPathComponent("logs"))
        XCTAssertFalse(unwritable.record(component: "test", operation: "write", code: "failed"))
        XCTAssertNil(unwritable.availableFileURL)
    }

    func testTightensExistingPermissionsAndBoundsOversizedFiles() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory, maximumFileSize: 512)
        let previous = directory.appendingPathComponent("errors.log.1")
        for file in [log.fileURL, previous] {
            try Data(repeating: 0x41, count: 1024).write(to: file)
            XCTAssertEqual(chmod(file.path, 0o644), 0)
        }
        XCTAssertEqual(chmod(directory.path, 0o755), 0)
        XCTAssertTrue(log.record(component: "test", operation: "write", code: "failed"))
        XCTAssertEqual(try permissions(at: directory), 0o700)
        for file in [log.fileURL, previous] {
            XCTAssertEqual(try permissions(at: file), 0o600)
            XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 512)
        }
        XCTAssertEqual(try records(at: log.fileURL).count, 1)
    }

    func testUnavailableForEmptyUnreadableOrNonregularCurrentFile() throws {
        let directory = try temporaryDirectory()
        let log = ErrorLog(directoryURL: directory)
        XCTAssertTrue(log.record(component: "test", operation: "write", code: "failed"))
        XCTAssertEqual(chmod(log.fileURL.path, 0), 0)
        XCTAssertNil(log.availableFileURL)
        XCTAssertEqual(chmod(log.fileURL.path, 0o600), 0)
        try Data().write(to: log.fileURL)
        XCTAssertNil(log.availableFileURL)
        try FileManager.default.removeItem(at: log.fileURL)
        XCTAssertEqual(mkfifo(log.fileURL.path, 0o600), 0)
        XCTAssertNil(log.availableFileURL)
        XCTAssertFalse(log.record(component: "test", operation: "write", code: "failed"))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func records(at url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.last, 0x0A)
        return try data.split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func compileWriter(in directory: URL) throws -> URL {
        let main = directory.appendingPathComponent("main.swift")
        let source = """
        import Foundation
        import Darwin
        enum KeychainError: Error {
            case saveFailed(Int32), loadFailed(Int32), deleteFailed(Int32)
        }
        let log = ErrorLog(
            directoryURL: URL(fileURLWithPath: CommandLine.arguments[1]),
            maximumFileSize: Int(CommandLine.arguments[2])!
        )
        for index in 0..<50 {
            guard log.record(
                component: "helper", operation: "write",
                code: "failure_\\(CommandLine.arguments[3])_\\(index)"
            ) else { exit(1) }
        }
        """
        try source.write(to: main, atomically: true, encoding: .utf8)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = directory.appendingPathComponent("writer")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        compiler.arguments = [
            root.appendingPathComponent("Sources/Core/ErrorLog.swift").path,
            root.appendingPathComponent("Sources/Core/DiagnosticError.swift").path,
            main.path, "-o", executable.path,
        ]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        return executable
    }
}
