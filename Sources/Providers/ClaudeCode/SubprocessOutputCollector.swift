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
/// One reader thread owns both streams, so a read can never race with
/// finalization: `finish` joins the reader before it takes the snapshot.
final class SubprocessOutputCollector: @unchecked Sendable {
    static let captureLimit = 65536

    private static let pollTimeoutMilliseconds: Int32 = 50
    private static let finalDrainDeadline: TimeInterval = 0.25
    private static let joinTimeout = DispatchTimeInterval.milliseconds(500)

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
    private let readerFinished = DispatchSemaphore(value: 0)
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

    func finish() -> CollectedSubprocessOutput {
        stop()
        let snapshot = state.withLock { $0 }
        return CollectedSubprocessOutput(
            stdout: snapshot.stdout,
            stdoutBytes: snapshot.stdoutBytes,
            stderrBytes: snapshot.stderrBytes,
            stdoutTruncated: snapshot.stdoutBytes > captureLimit
        )
    }

    func stop() {
        let alreadyStopped = shouldStop.withLock { stopped -> Bool in
            defer { stopped = true }
            return stopped
        }
        guard !alreadyStopped else { return }
        _ = readerFinished.wait(timeout: .now() + Self.joinTimeout)
    }

    private func readStreams() {
        var stdoutBuffer = [UInt8](repeating: 0, count: captureLimit)
        var stderrBuffer = [UInt8](repeating: 0, count: captureLimit)
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

        drainBuffered(descriptor: stdoutHandle.fileDescriptor, buffer: &stdoutBuffer, retaining: true)
        drainBuffered(descriptor: stderrHandle.fileDescriptor, buffer: &stderrBuffer, retaining: false)
        readerFinished.signal()
    }

    private func readAvailable(descriptor: Int32, buffer: inout [UInt8], retaining: Bool) -> Bool {
        let count = read(descriptor, &buffer, buffer.count)
        guard count > 0 else {
            let failure = errno
            return failure == EINTR || failure == EAGAIN || failure == EWOULDBLOCK
        }
        ingest(Data(bytes: buffer, count: count), retaining: retaining)
        return true
    }

    /// Reads only what is already buffered, bounded by a deadline so a
    /// descendant that keeps the write end open cannot extend finalization.
    private func drainBuffered(descriptor: Int32, buffer: inout [UInt8], retaining: Bool) {
        let original = fcntl(descriptor, F_GETFL)
        guard original >= 0, fcntl(descriptor, F_SETFL, original | O_NONBLOCK) == 0 else { return }
        defer { _ = fcntl(descriptor, F_SETFL, original) }
        let deadline = Date().addingTimeInterval(Self.finalDrainDeadline)
        while Date() < deadline {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            ingest(Data(bytes: buffer, count: count), retaining: retaining)
        }
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
