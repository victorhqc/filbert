@testable import ClaudeCodeProvider
import Darwin
import Foundation
import os
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

        let collected = try XCTUnwrap(collector.finish())

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
        let collected = try XCTUnwrap(collector.finish())
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 2, "a closed stdout must not stall finalization")
        XCTAssertTrue(collected.stdout.isEmpty)
        XCTAssertEqual(collected.stderrBytes, stderrPayload.count)
    }

    func testFinishIsBoundedWhileBothStreamsFlood() throws {
        let stdout = Pipe()
        let stderr = Pipe()
        let collector = SubprocessOutputCollector(
            stdoutHandle: stdout.fileHandleForReading,
            stderrHandle: stderr.fileHandleForReading
        )
        let flooding = OSAllocatedUnfairLock(initialState: true)
        let payload = Data(repeating: 0x41, count: 4096)
        for handle in [stdout.fileHandleForWriting, stderr.fileHandleForWriting] {
            setNonBlocking(handle.fileDescriptor)
            DispatchQueue.global().async {
                while flooding.withLock({ $0 }) {
                    payload.withUnsafeBytes { bytes in
                        _ = Darwin.write(handle.fileDescriptor, bytes.baseAddress, bytes.count)
                    }
                }
            }
        }

        let start = Date()
        let collected = try XCTUnwrap(collector.finish())
        flooding.withLock { $0 = false }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 3, "flooded streams must not extend finalization")
        XCTAssertTrue(collected.stdoutTruncated)
    }

    func testZeroReadIsEOFRegardlessOfStaleErrno() {
        XCTAssertEqual(SubprocessOutputCollector.classifyReadResult(count: 0, error: EAGAIN), .closed)
        XCTAssertEqual(SubprocessOutputCollector.classifyReadResult(count: 0, error: EINTR), .closed)
    }

    func testNegativeReadClassifiesByErrno() {
        XCTAssertEqual(SubprocessOutputCollector.classifyReadResult(count: -1, error: EAGAIN), .retry)
        XCTAssertEqual(SubprocessOutputCollector.classifyReadResult(count: -1, error: EINTR), .retry)
        XCTAssertEqual(SubprocessOutputCollector.classifyReadResult(count: -1, error: EIO), .closed)
    }

    func testPositiveReadClassifiesAsBytes() {
        XCTAssertEqual(SubprocessOutputCollector.classifyReadResult(count: 1, error: EAGAIN), .bytes)
    }

    private func setNonBlocking(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    }
}
