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

/// Spawns `claude --model haiku -p …` on demand to repopulate the statusline
/// cache, then terminates the process after a bounded wait (providers 03).
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

    /// Argv passed to the `claude` binary (providers 03 AC1). Each flag
    /// pulls its weight — see the spec's AC1 for the rationale per flag.
    static let spawnArguments: [String] = [
        "--model", "haiku",
        "-p",
        "--max-turns", "1",
        "--no-session-persistence",
        "--tools", "",
        "ok",
    ]

    private let locator: ClaudeCodeLocator
    private let spawnTimeout: TimeInterval
    private let terminateGrace: TimeInterval
    private let spawnDebounce: TimeInterval

    /// Timestamp of the most recent spawn *attempt* — successful or not —
    /// used to suppress follow-up clicks within the debounce window
    /// (providers 03 AC4). Cleared only by app restart; not persisted.
    private var lastSpawnAt: Date?

    /// Non-nil while a spawn task is in flight. Concurrent callers await this
    /// task instead of starting a second `claude` process (providers 03 AC4).
    private var inFlightTask: Task<Void, Error>?

    /// Production initializer — uses the real locator for binary resolution
    /// and the production timeout / debounce values.
    public init(locator: ClaudeCodeLocator = ClaudeCodeLocator()) {
        self.locator = locator
        spawnTimeout = Self.spawnTimeoutSeconds
        terminateGrace = Self.terminateGraceSeconds
        spawnDebounce = Self.spawnDebounceSeconds
    }

    /// Test-only initializer that overrides the timeout / debounce windows.
    /// Used by `ClaudeCodeRefresherTests` to keep the timeout test fast.
    init(
        locator: ClaudeCodeLocator,
        spawnTimeout: TimeInterval,
        terminateGrace: TimeInterval,
        spawnDebounce: TimeInterval
    ) {
        self.locator = locator
        self.spawnTimeout = spawnTimeout
        self.terminateGrace = terminateGrace
        self.spawnDebounce = spawnDebounce
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

        let task = Task<Void, Error> { [locator, spawnTimeout, terminateGrace] in
            try await Self.runSpawnOnce(
                locator: locator,
                spawnTimeout: spawnTimeout,
                terminateGrace: terminateGrace
            )
        }
        inFlightTask = task

        defer { inFlightTask = nil }

        try await task.value
    }

    // MARK: - Spawn lifecycle (providers 03 AC1, AC2)

    /// Resolves the binary, spawns it with the documented argv, waits for
    /// exit or the bounded timeout, and terminates the process on timeout.
    /// Non-timeout failures are logged and swallowed; only `binaryNotFound`
    /// is surfaced to the caller because the cache cannot be refreshed at
    /// all without the binary.
    private static func runSpawnOnce(
        locator: ClaudeCodeLocator,
        spawnTimeout: TimeInterval,
        terminateGrace: TimeInterval
    ) async throws {
        guard let binaryPath = locator.resolve() else {
            ClaudeCodeRefresherLog.log("runSpawnOnce: binary not found")
            throw ClaudeCodeRefresherError.binaryNotFound
        }

        let environment = makeSpawnEnvironment(forBinaryAt: binaryPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = spawnArguments
        // Standard streams are intentionally not redirected: the child
        // inherits the parent's descriptors, which for a GUI menu-bar app
        // effectively discard the response text. The cache write is the
        // only side effect we care about (providers 03 AC1).
        process.environment = environment

        ClaudeCodeRefresherLog.log(
            "runSpawnOnce: spawning \(binaryPath) \(spawnArguments.joined(separator: " "))"
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
