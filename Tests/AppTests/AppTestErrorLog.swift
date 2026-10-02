import Core
import Foundation

enum AppTestErrorLog {
    static func make() -> ErrorLog {
        ErrorLog(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
}
