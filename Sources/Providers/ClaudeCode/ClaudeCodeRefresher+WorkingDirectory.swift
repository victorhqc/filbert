import Foundation

extension ClaudeCodeRefresher {
    // MARK: - Working directory

    /// `temporaryDirectory` is per-user and outside TCC-protected locations, so
    /// the child cannot reach home, Documents, Desktop, or Downloads through
    /// working-directory discovery. `nil` aborts the spawn; the child never
    /// inherits the parent's working directory.
    static func makeDefaultWorkingDirectory() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-claude-code-spawn", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return url
    }
}
