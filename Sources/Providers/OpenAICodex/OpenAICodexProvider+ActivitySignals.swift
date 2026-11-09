import Core
import Foundation

extension OpenAICodexProvider: ActivitySignaling {
    public func activitySignals() -> AsyncStream<Date> {
        CodexActivityWatcher.signals(for: hooksInstaller.signalURL)
    }

    public func activitySignalStatus() async -> ActivitySignalStatus {
        guard isConfigured() else {
            return .unavailable(DisplayText { String(displayLocalized: "Codex CLI not installed", bundle: .module) })
        }
        return hooksInstaller.status()
    }

    public func installActivitySignal() async throws {
        guard isConfigured() else {
            throw OpenAICodexError.binaryNotFound
        }
        try hooksInstaller.install()
    }

    public func removeActivitySignal() async throws {
        try hooksInstaller.remove()
    }
}
