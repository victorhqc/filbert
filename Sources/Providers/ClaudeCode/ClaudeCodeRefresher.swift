import Core
import Foundation

// MARK: - Errors

public enum ClaudeCodeRefresherError: Error, Equatable, Sendable {
    case binaryNotFound
    case workingDirectoryUnavailable
    case processFailed(SubprocessDiagnostic)
    case timedOut
    case outputCollectionIncomplete
    case noUsageData(SubprocessDiagnostic)
}

extension ClaudeCodeRefresherError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            String(localized: "Claude Code not found. Install Claude Code and retry.")
        case .workingDirectoryUnavailable:
            String(localized: "Could not prepare Claude Code refresh. Retry the refresh.")
        case let .processFailed(diagnostic):
            Self.processFailureDescription(exitStatus: diagnostic.exitStatus)
        case .timedOut:
            String(localized: "Claude Code refresh timed out. Retry the refresh.")
        case .outputCollectionIncomplete:
            String(localized: "Claude Code refresh timed out. Retry the refresh.")
        case .noUsageData:
            String(localized: "Claude Code returned no usage data. Open Claude Code and retry.")
        }
    }

    private static func processFailureDescription(exitStatus: Int32) -> String {
        String(localized: "Claude Code refresh failed with exit code \(exitStatus). Open Claude Code and retry.")
    }
}

extension ClaudeCodeRefresherError: DiagnosticError {
    public var diagnosticCode: String {
        switch self {
        case .binaryNotFound: "binary-not-found"
        case .workingDirectoryUnavailable: "working-directory-unavailable"
        case .processFailed: "process-failed"
        case .timedOut: "refresh-timeout"
        case .outputCollectionIncomplete: "output-collection-incomplete"
        case .noUsageData: "usage-data-missing"
        }
    }

    public var diagnosticSubprocess: SubprocessDiagnostic? {
        switch self {
        case .binaryNotFound, .workingDirectoryUnavailable, .timedOut, .outputCollectionIncomplete: nil
        case let .processFailed(diagnostic), let .noUsageData(diagnostic): diagnostic
        }
    }
}

// MARK: - Refresher

private struct SpawnConfiguration: Sendable {
    let locator: ClaudeCodeLocator
    let cacheStore: StatuslineCacheStore
    let spawnTimeout: TimeInterval
    let terminateGrace: TimeInterval
    let workingDirectoryProvider: @Sendable () -> URL?
    let outputCaptureLimit: Int
}

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
    ///   - A `viewMode: "verbose"` or `verbose: true` user setting turns
    ///     `--output-format json` into a message array. `--safe-mode` does not
    ///     drop ordinary settings, so `--settings` pins the default view for
    ///     this run. Managed settings still win over it.
    static let spawnArguments: [String] = [
        "--model", "haiku",
        "--max-turns", "1",
        "--no-session-persistence",
        "--safe-mode",
        "--strict-mcp-config",
        "--no-chrome",
        "--settings", #"{"viewMode":"default"}"#,
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
    private let outputCaptureLimit: Int

    private var lastSpawnAt: Date?
    private var lastFailure: (any Error)?

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
        outputCaptureLimit = SubprocessOutputCollector.captureLimit
    }

    init(
        locator: ClaudeCodeLocator,
        cacheStore: StatuslineCacheStore = StatuslineCacheStore(),
        spawnTimeout: TimeInterval,
        terminateGrace: TimeInterval,
        spawnDebounce: TimeInterval,
        workingDirectoryProvider: @escaping @Sendable () -> URL? = {
            @Sendable in ClaudeCodeRefresher.makeDefaultWorkingDirectory()
        },
        outputCaptureLimit: Int = SubprocessOutputCollector.captureLimit
    ) {
        self.locator = locator
        self.cacheStore = cacheStore
        self.spawnTimeout = spawnTimeout
        self.terminateGrace = terminateGrace
        self.spawnDebounce = spawnDebounce
        self.workingDirectoryProvider = workingDirectoryProvider
        self.outputCaptureLimit = outputCaptureLimit
    }

    // MARK: - Public entry point

    public func refresh() async throws {
        // Coalesce before debounce: if a click arrives while a spawn is in
        // flight, it should await that result — checking debounce first would
        // short-circuit and miss the in-flight result.
        if let inFlightTask {
            try await inFlightTask.value
            return
        }

        if let lastSpawnAt {
            let elapsed = Date().timeIntervalSince(lastSpawnAt)
            if elapsed < spawnDebounce {
                if let lastFailure {
                    throw lastFailure
                }
                let cache = cacheStore.read()
                if cache?.rateLimits?.fiveHour?.populated != nil || cache?.rateLimits?.sevenDay?.populated != nil {
                    return
                }
            }
        }

        // Record the attempt *before* spawning so a failure still suppresses
        // follow-up clicks within the debounce window.
        lastSpawnAt = Date()

        let configuration = SpawnConfiguration(
            locator: locator,
            cacheStore: cacheStore,
            spawnTimeout: spawnTimeout,
            terminateGrace: terminateGrace,
            workingDirectoryProvider: workingDirectoryProvider,
            outputCaptureLimit: outputCaptureLimit
        )
        let task = Task<Void, Error> {
            try await Self.runSpawnOnce(configuration)
        }
        inFlightTask = task

        defer { inFlightTask = nil }

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            lastFailure = nil
        } catch {
            lastFailure = error is CancellationError ? nil : error
            throw error
        }
    }

    // MARK: - Spawn lifecycle

    private static func runSpawnOnce(_ configuration: SpawnConfiguration) async throws {
        try Task.checkCancellation()
        guard let binaryPath = configuration.locator.resolve() else {
            throw ClaudeCodeRefresherError.binaryNotFound
        }

        // Spawn inside an inert working directory so Claude Code's startup
        // CWD discovery does not touch macOS-protected user locations. If the
        // directory cannot be created, abort and leave the cache untouched —
        // never fall back to inheriting the parent's CWD.
        guard let workingDirectoryURL = configuration.workingDirectoryProvider() else {
            throw ClaudeCodeRefresherError.workingDirectoryUnavailable
        }

        let environment = makeSpawnEnvironment(forBinaryAt: binaryPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = spawnArguments
        process.currentDirectoryURL = workingDirectoryURL
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = environment

        let collector = SubprocessOutputCollector(
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading,
            captureLimit: configuration.outputCaptureLimit
        )
        defer { collector.stop() }

        try process.run()

        try await waitForExitOrTerminate(
            process,
            spawnTimeout: configuration.spawnTimeout,
            terminateGrace: configuration.terminateGrace
        )

        try Task.checkCancellation()

        guard let collected = collector.finish() else {
            throw ClaudeCodeRefresherError.outputCollectionIncomplete
        }
        try applySpawnResult(process: process, collected: collected, cacheStore: configuration.cacheStore)
    }

    private static func applySpawnResult(
        process: Process,
        collected: CollectedSubprocessOutput,
        cacheStore: StatuslineCacheStore
    ) throws {
        let validation = validateUsageOutput(
            collected.stdout,
            truncated: collected.stdoutTruncated
        )

        guard process.terminationStatus == 0 else {
            throw ClaudeCodeRefresherError.processFailed(diagnostic(
                collected: collected,
                exitStatus: process.terminationStatus,
                validation: validation
            ))
        }
        if let failure = validation.failure {
            throw ClaudeCodeRefresherError.noUsageData(diagnostic(
                collected: collected,
                exitStatus: process.terminationStatus,
                validation: validation,
                outputFailure: failure
            ))
        }

        try mergeAndWriteCache(windows: validation.windows, into: cacheStore)
    }

    private static func diagnostic(
        collected: CollectedSubprocessOutput,
        exitStatus: Int32,
        validation: UsageOutputValidation,
        outputFailure: OutputFailure? = nil
    ) -> SubprocessDiagnostic {
        SubprocessDiagnostic(
            exitStatus: exitStatus,
            stdoutBytes: collected.stdoutBytes,
            stderrBytes: collected.stderrBytes,
            stdoutTruncated: collected.stdoutTruncated,
            cliReportedError: validation.cliReportedError,
            outputFailure: outputFailure,
            stdoutJSONShape: validation.rootShape
        )
    }

    /// Uses `terminationHandler` + a continuation rather than `waitUntilExit`,
    /// because the latter is a blocking sync call that task-group cancellation
    /// cannot interrupt — racing it against `Task.sleep` inside a group would
    /// still wait for the process to actually die.
    private static func waitForExitOrTerminate(
        _ process: Process,
        spawnTimeout: TimeInterval,
        terminateGrace: TimeInterval
    ) async throws {
        let timeoutTask = Task<Bool, Never> {
            do {
                try await Task.sleep(for: .seconds(spawnTimeout))
            } catch { return false }
            guard process.isRunning else { return false }
            process.terminate()

            let graceStart = Date()
            let graceDeadline = graceStart.addingTimeInterval(terminateGrace)
            while process.isRunning, Date() < graceDeadline {
                try? await Task.sleep(for: .milliseconds(100))
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return true
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    timeoutTask.cancel()
                    continuation.resume()
                }
            }
        } onCancel: {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        try Task.checkCancellation()
        if await timeoutTask.value {
            throw ClaudeCodeRefresherError.timedOut
        }
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
