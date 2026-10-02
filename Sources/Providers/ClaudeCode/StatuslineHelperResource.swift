import Foundation

enum StatuslineHelperResource {
    static let executableName = "ClaudeCodeStatuslineHelper"

    static func resolve(
        resourceURL: URL? = Bundle.main.resourceURL,
        executableURL: URL? = Bundle.main.executableURL,
        moduleURL: URL = Bundle.module.bundleURL
    ) -> URL? {
        let candidates = [
            resourceURL?.appendingPathComponent(executableName),
            executableURL?.deletingLastPathComponent().appendingPathComponent(executableName),
            moduleURL.deletingLastPathComponent().appendingPathComponent(executableName),
            testBuildProductsURL(moduleURL)?.appendingPathComponent(executableName),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func testBuildProductsURL(_ moduleURL: URL) -> URL? {
        var directory = moduleURL.deletingLastPathComponent()
        while directory.path != "/" {
            if directory.pathExtension == "xctest" {
                return directory.deletingLastPathComponent()
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
