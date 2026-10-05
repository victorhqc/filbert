import Core
import Foundation

struct SafeDiagnosticFailure: DiagnosticError, LocalizedError {
    let diagnosticCode = "process-exited"
    var diagnosticSubprocess: SubprocessDiagnostic? {
        SubprocessDiagnostic(
            exitStatus: 17,
            stdoutBytes: 2048,
            stderrBytes: 96,
            stdoutTruncated: true,
            cliReportedError: false,
            outputFailure: .usageWindowsMissing
        )
    }

    var errorDescription: String? {
        "SECRET-response-body"
    }
}

struct SecretCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
