import Darwin
import Foundation
import os

struct CollectedSubprocessOutput {
    let stdout: Data
    let stdoutBytes: Int
    let stderrBytes: Int
    let stdoutTruncated: Bool
}

/// Drains a child's stdout and stderr while it runs so a full pipe cannot stall
/// the child. Retention is bounded; stderr is counted and never kept.
///
/// One reader thread owns both streams, and `finish` returns a snapshot only
/// after that thread reports completion. A reader that does not stop in time
/// yields `nil` rather than a partial snapshot.
final class SubprocessOutputCollector: @unchecked Sendable {
    static let captureLimit = 20 * 1024 * 1024

    private static let readChunkSize = 64 * 1024

    enum StreamReadOutcome: Equatable {
        case bytes
        case closed
        case retry
    }

    private static let pollTimeoutMilliseconds: Int32 = 50
    private static let finalDrainDeadline: TimeInterval = 0.25
    private static let joinTimeout: TimeInterval = 5

    private struct State {
        var stdout = Data()
        var stdoutBytes = 0
        var stderrBytes = 0
    }

    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let captureLimit: Int
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let shouldStop = OSAllocatedUnfairLock(initialState: false)
    private let completion = NSCondition()
    private var readerDone = false
    private var readerThread: Thread?

    init(
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        captureLimit: Int = SubprocessOutputCollector.captureLimit
    ) {
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
        self.captureLimit = captureLimit
        let thread = Thread { [weak self] in self?.readStreams() }
        readerThread = thread
        thread.start()
    }

    /// Returns `nil` when the reader did not stop within the join bound, so no
    /// snapshot is safe to use.
    func finish() -> CollectedSubprocessOutput? {
        stop()
        guard waitForReader() else { return nil }
        let snapshot = state.withLock { $0 }
        return CollectedSubprocessOutput(
            stdout: snapshot.stdout,
            stdoutBytes: snapshot.stdoutBytes,
            stderrBytes: snapshot.stderrBytes,
            stdoutTruncated: snapshot.stdoutBytes > captureLimit
        )
    }

    func stop() {
        shouldStop.withLock { $0 = true }
    }

    static func classifyReadResult(count: Int, error: Int32) -> StreamReadOutcome {
        if count > 0 {
            return .bytes
        }
        if count == 0 {
            return .closed
        }
        return error == EINTR || error == EAGAIN || error == EWOULDBLOCK ? .retry : .closed
    }

    private func waitForReader() -> Bool {
        completion.lock()
        defer { completion.unlock() }
        let deadline = Date().addingTimeInterval(Self.joinTimeout)
        while !readerDone {
            if !completion.wait(until: deadline) {
                return false
            }
        }
        return true
    }

    private func readStreams() {
        var stdoutBuffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        var stderrBuffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        var stdoutOpen = true
        var stderrOpen = true

        while stdoutOpen || stderrOpen, !shouldStop.withLock({ $0 }) {
            var descriptors = [
                pollfd(fd: stdoutOpen ? stdoutHandle.fileDescriptor : -1, events: Int16(POLLIN), revents: 0),
                pollfd(fd: stderrOpen ? stderrHandle.fileDescriptor : -1, events: Int16(POLLIN), revents: 0),
            ]
            let ready = poll(&descriptors, 2, Self.pollTimeoutMilliseconds)
            if ready < 0 {
                if errno == EINTR {
                    continue
                }
                break
            }
            if ready == 0 {
                continue
            }
            if stdoutOpen, descriptors[0].revents != 0 {
                stdoutOpen = readAvailable(
                    descriptor: stdoutHandle.fileDescriptor,
                    buffer: &stdoutBuffer,
                    retaining: true
                )
            }
            if stderrOpen, descriptors[1].revents != 0 {
                stderrOpen = readAvailable(
                    descriptor: stderrHandle.fileDescriptor,
                    buffer: &stderrBuffer,
                    retaining: false
                )
            }
        }

        let deadline = Date().addingTimeInterval(Self.finalDrainDeadline)
        drainBuffered(deadline: deadline, stdoutBuffer: &stdoutBuffer, stderrBuffer: &stderrBuffer)
        signalReaderFinished()
    }

    private func readAvailable(descriptor: Int32, buffer: inout [UInt8], retaining: Bool) -> Bool {
        let count = read(descriptor, &buffer, buffer.count)
        switch Self.classifyReadResult(count: count, error: errno) {
        case .bytes:
            ingest(Data(bytes: buffer, count: count), retaining: retaining)
            return true
        case .retry:
            return true
        case .closed:
            return false
        }
    }

    /// Drains only bytes already buffered. Both streams share one deadline, so a
    /// descendant that keeps the write end open cannot extend finalization.
    private func drainBuffered(deadline: Date, stdoutBuffer: inout [UInt8], stderrBuffer: inout [UInt8]) {
        let stdoutFlags = makeNonBlocking(descriptor: stdoutHandle.fileDescriptor)
        let stderrFlags = makeNonBlocking(descriptor: stderrHandle.fileDescriptor)
        defer {
            restoreFlags(descriptor: stdoutHandle.fileDescriptor, to: stdoutFlags)
            restoreFlags(descriptor: stderrHandle.fileDescriptor, to: stderrFlags)
        }
        while Date() < deadline {
            let stdoutCount = read(stdoutHandle.fileDescriptor, &stdoutBuffer, stdoutBuffer.count)
            if stdoutCount > 0 {
                ingest(Data(bytes: stdoutBuffer, count: stdoutCount), retaining: true)
            }
            let stderrCount = read(stderrHandle.fileDescriptor, &stderrBuffer, stderrBuffer.count)
            if stderrCount > 0 {
                ingest(Data(bytes: stderrBuffer, count: stderrCount), retaining: false)
            }
            if stdoutCount <= 0, stderrCount <= 0 {
                break
            }
        }
    }

    private func makeNonBlocking(descriptor: Int32) -> Int32 {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return -1 }
        return flags
    }

    private func restoreFlags(descriptor: Int32, to flags: Int32) {
        guard flags >= 0 else { return }
        _ = fcntl(descriptor, F_SETFL, flags)
    }

    private func signalReaderFinished() {
        completion.lock()
        readerDone = true
        completion.broadcast()
        completion.unlock()
    }

    private func ingest(_ data: Data, retaining: Bool) {
        guard !data.isEmpty else { return }
        state.withLock { state in
            guard retaining else {
                state.stderrBytes += data.count
                return
            }
            state.stdoutBytes += data.count
            let remaining = captureLimit - state.stdout.count
            if remaining > 0 {
                state.stdout.append(data.prefix(remaining))
            }
        }
    }
}
