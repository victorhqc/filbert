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

/// Runs `claude -p "/usage"` and writes the parsed figures to the cache. The
/// statusline helper runs only in the interactive TUI, so this makes Refresh
/// work for editor users, e.g. Zed.
///
/// Spawn work runs in a child `Task`, so `Process.run` and `waitUntilExit`
/// never block the actor.
public actor ClaudeCodeRefresher {
    static let spawnTimeoutSeconds: TimeInterval = 30

    static let terminateGraceSeconds: TimeInterval = 2

    static let spawnDebounceSeconds: TimeInterval = 10

    /// - `--tools ""` is variadic. A flag must follow it, or it swallows the prompt
    ///   and `claude` fails with "Input must be provided". `-p "/usage"` stays last.
    /// - `--strict-mcp-config` without `--mcp-config` loads no MCP server.
    /// - `--safe-mode` and `--no-chrome` skip startup discovery (CLAUDE.md, skills,
    ///   plugins, hooks, MCP servers, status-line commands), so the child cannot
    ///   probe protected user locations.
    /// - `--bare` is absent: it disables the OAuth/Keychain login the refresh reuses.
    /// - A `viewMode: "verbose"` or `verbose: true` setting turns `--output-format
    ///   json` into a message array. `--safe-mode` keeps ordinary settings, so
    ///   `--settings` pins the default view. Managed settings still win.
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
        // Check in-flight work before the debounce, or a click during a spawn
        // misses that spawn's result.
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

        // Set before spawning, so a failed spawn still debounces later clicks.
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

        // Never fall back to the parent's working directory; abort instead.
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

    /// `waitUntilExit` blocks and ignores task cancellation, so a timeout race
    /// would still wait for the process to die. `terminationHandler` does not.
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
