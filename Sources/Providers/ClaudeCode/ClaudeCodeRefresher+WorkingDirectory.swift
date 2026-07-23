import Foundation

extension ClaudeCodeRefresher {
    // MARK: - Working directory (providers 06 AC1)

    /// Creates an AI Usage-owned directory below
    /// `FileManager.default.temporaryDirectory` for the `claude` child to run
    /// in. Returns `nil` if creation fails, in which case the caller aborts
    /// the spawn and leaves the cache untouched.
    ///
    /// The directory is intentionally *not* the user's home, Documents,
    /// Desktop, Downloads, Music, the app's source checkout, or any
    /// user-selected project: `temporaryDirectory` is per-user but lives
    /// outside TCC-protected locations, so a child spawned here cannot reach
    /// those locations through CWD/parent-walk discovery at startup
    /// (providers 06 AC1).
    static func makeDefaultWorkingDirectory() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-claude-code-spawn", isDirectory: true)
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
