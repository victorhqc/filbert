/// A fixed set of reasons a subprocess's standard output did not yield usage
/// data. Values are recorded verbatim, so they must never carry process text.
public enum OutputFailure: String, Sendable, Equatable, CaseIterable, Encodable {
    case outputTooLarge = "output-too-large"
    case emptyOutput = "empty-output"
    case invalidJSON = "invalid-json"
    case invalidEnvelope = "invalid-envelope"
    case cliReportedError = "cli-reported-error"
    case resultMissing = "result-missing"
    case resultInvalid = "result-invalid"
    case usageWindowsMissing = "usage-windows-missing"
}

/// Safe metadata about a completed subprocess run. Numeric and Boolean values
/// only; captured process output never passes through this type.
public struct SubprocessDiagnostic: Sendable, Equatable {
    public var exitStatus: Int32
    public var stdoutBytes: Int
    public var stderrBytes: Int
    public var stdoutTruncated: Bool
    public var cliReportedError: Bool?
    public var outputFailure: OutputFailure?

    public init(
        exitStatus: Int32,
        stdoutBytes: Int,
        stderrBytes: Int,
        stdoutTruncated: Bool,
        cliReportedError: Bool? = nil,
        outputFailure: OutputFailure? = nil
    ) {
        self.exitStatus = exitStatus
        self.stdoutBytes = stdoutBytes
        self.stderrBytes = stderrBytes
        self.stdoutTruncated = stdoutTruncated
        self.cliReportedError = cliReportedError
        self.outputFailure = outputFailure
    }
}

/// Diagnostic identifiers must be constants, not credentials or external system output.
public protocol DiagnosticError: Error {
    var diagnosticCode: String { get }
    var diagnosticSubprocess: SubprocessDiagnostic? { get }
}

public extension DiagnosticError {
    var diagnosticSubprocess: SubprocessDiagnostic? {
        nil
    }
}
