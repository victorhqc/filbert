import Core
import Foundation

// MARK: - Diagnostic logging

enum ClaudeCodeRefresherLog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(
            Data("[ClaudeCodeRefresher] \(message())\n".utf8)
        )
    }
}

// MARK: - Errors

/// All errors are diagnostic-only: the provider swallows them and reads
/// whatever cache exists, so they never surface to the UI as fetch failures.
public enum ClaudeCodeRefresherError: Error, Equatable, Sendable {
    case binaryNotFound

    public static func == (lhs: ClaudeCodeRefresherError, rhs: ClaudeCodeRefresherError) -> Bool {
        switch (lhs, rhs) {
        case (.binaryNotFound, .binaryNotFound): true
        }
    }
}

// MARK: - Refresher

/// Spawns `claude -p "/usage"` headlessly and parses the same `NN% used ·
/// resets …` figures the TUI shows, then writes the cache. The TUI statusline
/// helper only fires inside Claude Code's interactive session; this path makes
/// the Refresh button work for users who drive Claude Code through an editor
/// (e.g. Zed) and never open the TUI.
///
/// An `actor` serializes the debounce timestamp and the in-flight task slot;
/// all spawn work happens inside a child `Task` so the actor itself is never
/// blocked by `Process.run` / `waitUntilExit`.
public actor ClaudeCodeRefresher {
    static let spawnTimeoutSeconds: TimeInterval = 30

    static let terminateGraceSeconds: TimeInterval = 2

    static let spawnDebounceSeconds: TimeInterval = 10

    /// Notes on the non-obvious flags:
    ///   - `--tools ""` is variadic, so it must be followed by another *flag* —
    ///     never by the positional prompt — otherwise it swallows the prompt
    ///     and `claude` errors with "Input must be provided … when using
    ///     --print". Keeping `-p "/usage"` last makes the positional prompt
    ///     unambiguous.
    ///   - `--strict-mcp-config` is passed without a sibling `--mcp-config`,
    ///     so no user, project, or local MCP server is loaded.
    ///   - `--safe-mode` and `--no-chrome` suppress Claude Code's startup
    ///     discovery surface (CLAUDE.md walk, skills, plugins, hooks, MCP
    ///     servers, output styles, status-line commands, …) so a child that
    ///     inherits an inert working directory cannot probe macOS-protected
    ///     user locations at startup.
    ///   - `--bare` is deliberately absent: it would disable the OAuth/Keychain
    ///     login the refresh must reuse.
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

    private var lastSpawnAt: Date?

    private var inFlightTask: Task<Void, Error>?

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

    // MARK: - Public entry point

    public func refresh() async throws {
        // Coalesce before debounce: if a click arrives while a spawn is in
        // flight, it should await that result — checking debounce first would
        // short-circuit and miss the in-flight result.
        if let inFlightTask {
            ClaudeCodeRefresherLog.log("refresh: awaiting in-flight spawn")
            try await inFlightTask.value
            return
        }

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
        // follow-up clicks within the debounce window.
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

    // MARK: - Spawn lifecycle

    /// When stdout yields no usage figures (spawn failed, logged out, CLI
    /// drift), the cache is left untouched so a failed refresh never clobbers
    /// previously good data. Only `binaryNotFound` is surfaced.
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

        // Spawn inside an inert working directory so Claude Code's startup
        // CWD discovery does not touch macOS-protected user locations. If the
        // directory cannot be created, abort and leave the cache untouched —
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
        // stderr is discarded: we never surface the child's diagnostics, and
        // dropping it keeps a GUI menu-bar app quiet.
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

    // MARK: - Environment

    private static func makeSpawnEnvironment(forBinaryAt binaryPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let binaryDir = (binaryPath as NSString).deletingLastPathComponent
        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = "\(binaryDir):\(currentPath)"
        return environment
    }
}
