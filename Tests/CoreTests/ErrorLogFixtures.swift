import Core
import Foundation

struct SafeDiagnosticFailure: DiagnosticError, LocalizedError {
    let diagnosticCode = "process-exited"
    let diagnosticExitStatus: Int32? = 17
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
