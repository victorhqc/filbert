import Foundation

public enum ActivitySignalStatus: Sendable {
    case notInstalled(DisplayText?)
    case awaitingFirstSignal(DisplayText?)
    case active
    case unavailable(DisplayText)
}

/// Opt-in: a provider whose own client can tell Filbert that the user is
/// working, so Smart refresh can speed up before usage changes.
///
/// A signal carries only its time. Never forward prompts, paths, or other
/// client data. A fetch by Filbert must never produce a signal, or each
/// refresh would schedule the next one.
public protocol ActivitySignaling: AIProvider {
    /// Each call returns a new stream. Stop watching the source when that
    /// stream terminates.
    func activitySignals() -> AsyncStream<Date>

    /// Read from the source on every call, so changes made outside Filbert
    /// show up at the next read.
    func activitySignalStatus() async -> ActivitySignalStatus

    func installActivitySignal() async throws

    func removeActivitySignal() async throws
}
