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
final class SubprocessOutputCollector: @unchecked Sendable {
    static let captureLimit = 65536

    private struct State {
        var stdout = Data()
        var stdoutBytes = 0
        var stderrBytes = 0
    }

    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let captureLimit: Int
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        captureLimit: Int = SubprocessOutputCollector.captureLimit
    ) {
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
        self.captureLimit = captureLimit
        stdoutHandle.readabilityHandler = { [weak self] handle in
            self?.ingest(handle.availableData, retaining: true)
        }
        stderrHandle.readabilityHandler = { [weak self] handle in
            self?.ingest(handle.availableData, retaining: false)
        }
    }

    func finish() -> CollectedSubprocessOutput {
        stop()
        drainAvailable(stdoutHandle.fileDescriptor, retaining: true)
        drainAvailable(stderrHandle.fileDescriptor, retaining: false)
        let snapshot = state.withLock { $0 }
        return CollectedSubprocessOutput(
            stdout: snapshot.stdout,
            stdoutBytes: snapshot.stdoutBytes,
            stderrBytes: snapshot.stderrBytes,
            stdoutTruncated: snapshot.stdoutBytes > captureLimit
        )
    }

    func stop() {
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
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

    /// Reads only what is already buffered, so a descendant that keeps the
    /// write end open cannot extend the refresh waiting for EOF.
    private func drainAvailable(_ descriptor: Int32, retaining: Bool) {
        let original = fcntl(descriptor, F_GETFL)
        guard original >= 0, fcntl(descriptor, F_SETFL, original | O_NONBLOCK) == 0 else { return }
        defer { _ = fcntl(descriptor, F_SETFL, original) }
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            ingest(Data(bytes: buffer, count: count), retaining: retaining)
        }
    }
}
