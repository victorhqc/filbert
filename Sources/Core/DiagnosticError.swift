/// Diagnostic identifiers must be constants, not credentials or external system output.
public protocol DiagnosticError: Error {
    var diagnosticCode: String { get }
    var diagnosticExitStatus: Int32? { get }
}

public extension DiagnosticError {
    var diagnosticExitStatus: Int32? {
        nil
    }
}
