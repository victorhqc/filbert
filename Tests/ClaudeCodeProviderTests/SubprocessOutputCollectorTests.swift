@testable import ClaudeCodeProvider
import Foundation
import XCTest

final class SubprocessOutputCollectorTests: XCTestCase {
    func testFinishCapturesBytesBufferedBeforeStop() throws {
        let stdout = Pipe()
        let stderr = Pipe()
        let collector = SubprocessOutputCollector(
            stdoutHandle: stdout.fileHandleForReading,
            stderrHandle: stderr.fileHandleForReading
        )
        let payload = Data(repeating: 0x41, count: 96 * 1024)
        try stdout.fileHandleForWriting.write(contentsOf: payload)

        let collected = collector.finish()

        XCTAssertEqual(collected.stdoutBytes, payload.count)
        XCTAssertEqual(collected.stdout.count, SubprocessOutputCollector.captureLimit)
        XCTAssertTrue(collected.stdoutTruncated)
    }

    func testClosedStreamDoesNotBlockTheOtherStream() throws {
        let stdout = Pipe()
        let stderr = Pipe()
        let collector = SubprocessOutputCollector(
            stdoutHandle: stdout.fileHandleForReading,
            stderrHandle: stderr.fileHandleForReading
        )
        try stdout.fileHandleForWriting.close()
        let stderrPayload = Data("stderr-while-open".utf8)
        try stderr.fileHandleForWriting.write(contentsOf: stderrPayload)

        let start = Date()
        let collected = collector.finish()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 2, "a closed stdout must not stall finalization")
        XCTAssertTrue(collected.stdout.isEmpty)
        XCTAssertEqual(collected.stderrBytes, stderrPayload.count)
    }
}
