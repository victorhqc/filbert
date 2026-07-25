import Core
import Foundation

// MARK: - Diagnostic logging

/// Lightweight stderr logger shared by the refresher. Mirrors the pattern in
/// `ClaudeCodeLog` so all Claude Code diagnostics land in the same shape.
enum ClaudeCodeRefresherLog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(
            Data("[ClaudeCodeRefresher] \(message())\n".utf8)
        )
    }
}

// MARK: - Errors (providers 03 AC2)

/// Errors thrown by `ClaudeCodeRefresher.refresh()`. All of them are
/// diagnostic-only: the provider swallows them and reads whatever cache
/// exists (providers 03 AC3), so they never surface to the UI as fetch
/// failures.
public enum ClaudeCodeRefresherError: Error, Equatable, Sendable {
    /// The `claude` binary could not be resolved via `ClaudeCodeLocator`
    /// (providers 03 AC1, mirroring providers 02 AC1).
    case binaryNotFound

    public static func == (lhs: ClaudeCodeRefresherError, rhs: ClaudeCodeRefresherError) -> Bool {
        switch (lhs, rhs) {
        case (.binaryNotFound, .binaryNotFound): true
        }
    }
}

// MARK: - Refresher (providers 03 AC1, AC2, AC4, AC5)

/// Spawns `claude -p "/usage"` on demand, parses the usage percentages and
/// reset times out of that command's text output, and writes the shared
/// cache — then terminates the process after a bounded wait (providers 03).
///
/// This is the headless refresh path. Unlike the statusline helper
/// (providers 02), which only fires inside Claude Code's interactive TUI, a
/// `claude -p` run never renders a status line — so the refresher cannot rely
/// on the helper being invoked. Instead it runs the `/usage` command (which
/// prints the same `NN% used · resets …` figures the TUI shows) and writes
/// the cache itself. This makes the Refresh button work for users who drive
/// Claude Code through an editor (e.g. Zed) and never open the TUI.
///
/// The refresher is an `actor` because the debounce timestamp and the
/// in-flight task slot both need serialized mutation (providers 03 AC4).
/// All spawn work happens inside a child `Task` so the actor itself is never
/// blocked by `Process.run` / `waitUntilExit`.
public actor ClaudeCodeRefresher {
    /// Maximum wall-clock seconds to wait for `claude -p` to exit on its own
    /// before terminating it (providers 03 AC2). Haiku + `--max-turns 1`
    /// typically finishes in 1–3s; this is a safety net for network hiccups.
    static let spawnTimeoutSeconds: TimeInterval = 30

    /// Grace period between `SIGTERM` and `SIGKILL` (providers 03 AC2).
    static let terminateGraceSeconds: TimeInterval = 2

    /// Minimum seconds between two spawns (providers 03 AC4). Matches the
    /// read-debounce window in (providers 02 AC9) so a spawn and a re-read
    /// share the same cadence.
    static let spawnDebounceSeconds: TimeInterval = 60

    /// Argv passed to the `claude` binary (providers 03 AC1, revised by
    /// providers 06 AC2). Notes on order and choice:
    ///   - `-p "/usage"` runs the built-in usage command non-interactively;
    ///     its text output carries the session (5-hour) and week (7-day)
    ///     percentages and reset times.
    ///   - `--output-format json` wraps that text in a single JSON object so
    ///     we read it cleanly from the `result` field (no `--verbose` needed,
    ///     unlike `stream-json`).
    ///   - `--model haiku` / `--max-turns 1` bound the work in case `/usage`
    ///     ever triggers a model turn; `/usage` is otherwise model-free.
    ///   - `--no-session-persistence` avoids a throwaway session on disk.
    ///   - `--tools ""` disables every tool (CLI: `""` means "no tools"). It
    ///     is variadic, so it must be followed by another *flag* — never by
    ///     the positional prompt — otherwise it swallows the prompt and
    ///     `claude` errors with "Input must be provided … when using --print".
    ///     Keeping `-p "/usage"` last makes the positional prompt unambiguous.
    ///   - `--safe-mode`, `--strict-mcp-config`, and `--no-chrome` suppress
    ///     Claude Code's startup discovery surface — CLAUDE.md files, skills,
    ///     plugins, hooks, MCP servers, custom commands/agents, output styles,
    ///     status-line commands, LSP servers, auto-memory, and Chrome init —
    ///     so a child that inherits an inert working directory cannot probe
    ///     macOS-protected user locations during startup (providers 06 AC1,
    ///     AC2). These are *startup-isolation* flags, not Claude tool-
    ///     permission modes: they neither grant, deny, nor suppress a macOS
    ///     TCC decision, and `--permission-mode bypassPermissions` /
    ///     `--dangerously-skip-permissions` are deliberately absent
    ///     (providers 06 AC3). `--strict-mcp-config` is passed without a
    ///     sibling `--mcp-config`, so no user, project, or local MCP server
    ///     is loaded. `--bare` is also deliberately absent: it would disable
    ///     the OAuth/Keychain login the refresh must reuse.
    static let spawnArguments: [String] = [
        "--model", "haiku",
        "--max-turns", "1",
        "--no-session-persistence",
        "--safe-mode",
        "--strict-mcp-config",
        "--no-chrome",
        "--tools", "",
        "--output-format", "json",
        "-p", "/usage",
    ]

    private let locator: ClaudeCodeLocator
    private let cacheStore: StatuslineCacheStore
    private let spawnTimeout: TimeInterval
    private let terminateGrace: TimeInterval
    private let spawnDebounce: TimeInterval
    private let workingDirectoryProvider: @Sendable () -> URL?

    /// Timestamp of the most recent spawn *attempt* — successful or not —
    /// used to suppress follow-up clicks within the debounce window
    /// (providers 03 AC4). Cleared only by app restart; not persisted.
    private var lastSpawnAt: Date?

    /// Non-nil while a spawn task is in flight. Concurrent callers await this
    /// task instead of starting a second `claude` process (providers 03 AC4).
    private var inFlightTask: Task<Void, Error>?

    /// Production initializer — uses the real locator for binary resolution,
    /// the shared cache store, and the production timeout / debounce values.
    public init(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(),
        cacheStore: StatuslineCacheStore = StatuslineCacheStore()
    ) {
        self.locator = locator
        self.cacheStore = cacheStore
        spawnTimeout = Self.spawnTimeoutSeconds
        terminateGrace = Self.terminateGraceSeconds
        spawnDebounce = Self.spawnDebounceSeconds
        workingDirectoryProvider = { @Sendable in Self.makeDefaultWorkingDirectory() }
    }

    /// Test-only initializer that overrides the cache store and the timeout /
    /// debounce windows. Used by `ClaudeCodeRefresherTests` to point the cache
    /// at a temp file and keep the timeout test fast.
    init(
        locator: ClaudeCodeLocator,
        cacheStore: StatuslineCacheStore = StatuslineCacheStore(),
        spawnTimeout: TimeInterval,
        terminateGrace: TimeInterval,
        spawnDebounce: TimeInterval,
        workingDirectoryProvider: @escaping @Sendable () -> URL? = {
            @Sendable in ClaudeCodeRefresher.makeDefaultWorkingDirectory()
        }
    ) {
        self.locator = locator
        self.cacheStore = cacheStore
        self.spawnTimeout = spawnTimeout
        self.terminateGrace = terminateGrace
        self.spawnDebounce = spawnDebounce
        self.workingDirectoryProvider = workingDirectoryProvider
    }

    // MARK: - Public entry point (providers 03 AC1, AC2, AC4)

    /// Triggers a spawn unless one is in flight or the debounce window has
    /// not yet elapsed. Always returns without throwing on spawn failure —
    /// the provider reads whatever cache exists regardless (providers 03 AC3).
    ///
    /// The only error this surfaces is `binaryNotFound`, which the provider
    /// maps to "No data" alongside any prior cache content. All other spawn
    /// failures (non-zero exit, timeout, SIGKILL) are diagnostic-only.
    public func refresh() async throws {
        // Coalesce first: if a spawn is in flight, await it instead of
        // starting a second `claude` process (providers 03 AC4). This check
        // must come before the debounce check, otherwise a click that arrives
        // while a spawn is running would short-circuit and miss the chance
        // to await the in-flight result.
        if let inFlightTask {
            ClaudeCodeRefresherLog.log("refresh: awaiting in-flight spawn")
            try await inFlightTask.value
            return
        }

        // Debounce: a spawn attempt within the window returns immediately
        // (providers 03 AC4). The cache read in AC3 still happens on the
        // caller side, so the user sees the most recent data we have.
        if let lastSpawnAt {
            let elapsed = Date().timeIntervalSince(lastSpawnAt)
            if elapsed < spawnDebounce {
                ClaudeCodeRefresherLog.log(
                    "refresh: debounced (elapsed=\(Int(elapsed))s)"
                )
                return
            }
        }

        // Record the attempt *before* spawning so a failure still suppresses
        // follow-up clicks within the debounce window (providers 03 AC4).
        lastSpawnAt = Date()

        let task = Task<Void, Error> { [locator, cacheStore, spawnTimeout, terminateGrace, workingDirectoryProvider] in
            try await Self.runSpawnOnce(
                locator: locator,
                cacheStore: cacheStore,
                spawnTimeout: spawnTimeout,
                terminateGrace: terminateGrace,
                workingDirectoryProvider: workingDirectoryProvider
            )
        }
        inFlightTask = task

        defer { inFlightTask = nil }

        try await task.value
    }

    // MARK: - Spawn lifecycle (providers 03 AC1, AC2)

    /// Resolves the binary, spawns it with the documented argv, waits for
    /// exit or the bounded timeout, then parses the captured stdout and writes
    /// the cache. Non-timeout failures are logged and swallowed; only
    /// `binaryNotFound` is surfaced to the caller because nothing can be
    /// refreshed without the binary. When stdout yields no `rate_limit_event`
    /// (spawn failed, logged out, CLI drift), the cache is left untouched so a
    /// failed refresh never clobbers previously good data (providers 03 AC6).
    private static func runSpawnOnce(
        locator: ClaudeCodeLocator,
        cacheStore: StatuslineCacheStore,
        spawnTimeout: TimeInterval,
        terminateGrace: TimeInterval,
        workingDirectoryProvider: @Sendable () -> URL?
    ) async throws {
        guard let binaryPath = locator.resolve() else {
            ClaudeCodeRefresherLog.log("runSpawnOnce: binary not found")
            throw ClaudeCodeRefresherError.binaryNotFound
        }

        // Spawn inside a dedicated, inert working directory so Claude Code's
        // startup CWD discovery (CLAUDE.md walk, project state) does not touch
        // macOS-protected user locations (providers 06 AC1). If the directory
        // cannot be created, abort this attempt and leave the cache untouched —
        // never fall back to inheriting the parent's CWD.
        guard let workingDirectoryURL = workingDirectoryProvider() else {
            ClaudeCodeRefresherLog.log(
                "runSpawnOnce: working directory creation failed — aborting spawn, cache left as-is"
            )
            return
        }

        let environment = makeSpawnEnvironment(forBinaryAt: binaryPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = spawnArguments
        process.currentDirectoryURL = workingDirectoryURL
        // Capture stdout — that's where the `rate_limit_event` lands in
        // stream-json mode. stderr is discarded: we never surface the child's
        // diagnostics, and dropping it keeps a GUI menu-bar app quiet.
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        process.environment = environment

        ClaudeCodeRefresherLog.log(
            "runSpawnOnce: spawning \(binaryPath) argv=\(spawnArguments.joined(separator: " "))"
        )
        ClaudeCodeRefresherLog.log(
            "runSpawnOnce: cwd=\(workingDirectoryURL.path)"
        )

        do {
            try process.run()
        } catch {
            ClaudeCodeRefresherLog.log(
                "runSpawnOnce: process.run failed: \(error.localizedDescription)"
            )
            return
        }

        await waitForExitOrTerminate(
            process,
            spawnTimeout: spawnTimeout,
            terminateGrace: terminateGrace
        )

        // Read after exit: the `/usage` JSON output is a few KB — well under
        // the OS pipe buffer — so no concurrent drain is needed to avoid a
        // write-side stall. Once the process is reaped the write end is closed
        // and this returns immediately.
        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        let windows = parseUsageWindows(fromUsageJSON: output)
        guard !windows.isEmpty else {
            ClaudeCodeRefresherLog.log(
                "runSpawnOnce: no usage figures in \(output.count) bytes of stdout — cache left as-is"
            )
            return
        }

        mergeAndWriteCache(windows: windows, into: cacheStore)
    }

    /// Awaits process exit via `terminationHandler`, with a bounded timeout
    /// running in parallel. On timeout, escalates from `SIGTERM` to `SIGKILL`
    /// after the grace period (providers 03 AC2).
    ///
    /// Uses `terminationHandler` + a continuation rather than `waitUntilExit`,
    /// because the latter is a blocking sync call that task-group cancellation
    /// cannot interrupt — racing it against `Task.sleep` inside a group would
    /// still wait for the process to actually die.
    private static func waitForExitOrTerminate(
        _ process: Process,
        spawnTimeout: TimeInterval,
        terminateGrace: TimeInterval
    ) async {
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(spawnTimeout))
            if Task.isCancelled {
                return
            }
            guard process.isRunning else { return }

            ClaudeCodeRefresherLog.log(
                "waitForExitOrTerminate: timeout reached, sending SIGTERM"
            )
            // `interrupt()` sends SIGTERM on macOS (Process docs).
            process.interrupt()

            // Grace period before escalating to SIGKILL.
            let graceStart = Date()
            let graceDeadline = graceStart.addingTimeInterval(terminateGrace)
            while process.isRunning, Date() < graceDeadline {
                try? await Task.sleep(for: .milliseconds(100))
            }

            if process.isRunning {
                ClaudeCodeRefresherLog.log(
                    "waitForExitOrTerminate: SIGTERM did not take, sending SIGKILL"
                )
                kill(process.processIdentifier, SIGKILL)
            }
            // SIGKILL (or SIGTERM) will fire the terminationHandler, which
            // resumes the continuation below.
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Setting `terminationHandler` after `process.run()` is safe: if
            // the process has already exited, Foundation invokes the handler
            // synchronously on assignment.
            process.terminationHandler = { _ in
                timeoutTask.cancel()
                continuation.resume()
            }
        }

        ClaudeCodeRefresherLog.log(
            "waitForExitOrTerminate: reaped status=\(process.terminationStatus)"
        )
    }

    // MARK: - Environment (providers 03 AC1)

    /// Builds the environment for the spawned `claude` process. We inherit
    /// the parent environment and ensure the binary's own directory is on
    /// `PATH` so Claude Code's own subprocess lookups still succeed
    /// (providers 03 AC1).
    private static func makeSpawnEnvironment(forBinaryAt binaryPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let binaryDir = (binaryPath as NSString).deletingLastPathComponent
        let currentPath = environment["PATH"] ?? ""
        // Prepend so the resolved binary's directory takes precedence,
        // matching how Claude Code itself was located.
        environment["PATH"] = "\(binaryDir):\(currentPath)"
        return environment
    }
}
