import Core
import Foundation
import os

extension CodexAppServerError: DiagnosticError {
    var diagnosticCode: String {
        switch self {
        case .launchFailed: "launch-failed"
        case .unsupportedVersion: "unsupported-version"
        case .signedOut: "signed-out"
        case .childExited: "child-exited"
        case .malformedResponse: "malformed-response"
        case .timedOut: "timed-out"
        }
    }
}

struct CodexAppServerFailure: Error, Sendable {
    let reason: CodexAppServerError
    let subprocess: SubprocessDiagnostic?
}

extension CodexAppServerFailure: DiagnosticError, LocalizedError {
    var diagnosticCode: String {
        reason.diagnosticCode
    }

    var diagnosticSubprocess: SubprocessDiagnostic? {
        subprocess
    }

    var errorDescription: String? {
        reason.errorDescription
    }
}

final class CodexProcessUsage: Sendable {
    private struct State {
        var exitStatus: Int32?
        var stdoutBytes = 0
        var stderrBytes = 0
        var isStderrClosed = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func recordExit(_ status: Int32) {
        state.withLock { $0.exitStatus = status }
    }

    func addStdoutBytes(_ count: Int) {
        state.withLock { $0.stdoutBytes += count }
    }

    func addStderrBytes(_ count: Int) {
        state.withLock { $0.stderrBytes += count }
    }

    func recordStderrClosed() {
        state.withLock { $0.isStderrClosed = true }
    }

    /// Waits up to one second for the exit status and stderr EOF. A grandchild
    /// can hold stderr open, so the count may be partial; without an exit
    /// status the diagnostic is omitted.
    func diagnostic() async -> SubprocessDiagnostic? {
        for _ in 0 ..< 20 {
            if state.withLock({ $0.exitStatus != nil && $0.isStderrClosed }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return state.withLock { state in
            state.exitStatus.map { exitStatus in
                SubprocessDiagnostic(
                    exitStatus: exitStatus,
                    stdoutBytes: state.stdoutBytes,
                    stderrBytes: state.stderrBytes,
                    stdoutTruncated: false
                )
            }
        }
    }
}
