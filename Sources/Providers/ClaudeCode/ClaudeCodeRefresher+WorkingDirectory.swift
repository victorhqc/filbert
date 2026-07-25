import Foundation

extension ClaudeCodeRefresher {
    // MARK: - Working directory

    /// `temporaryDirectory` is per-user but lives outside TCC-protected
    /// locations, so a child spawned here cannot reach home, Documents,
    /// Desktop, Downloads, etc. through CWD/parent-walk discovery at startup.
    /// Returns `nil` if creation fails; the caller then aborts the spawn and
    /// leaves the cache untouched — never fall back to inheriting the
    /// parent's CWD.
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
            ClaudeCodeRefresherLog.log(
                "makeDefaultWorkingDirectory: failed to create \(url.path): \(error.localizedDescription)"
            )
            return nil
        }
        return url
    }
}
