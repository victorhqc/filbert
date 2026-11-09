import Core
import Foundation
import Observation

enum ActivityDetectionNoticeDismissals {
    static let key = "activity-detection-dismissed-notices"

    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    static func setUserDefaults(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    static var providerIds: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func setDismissed(_ dismissed: Bool, for providerId: String) {
        var ids = providerIds
        if dismissed {
            ids.insert(providerId)
        } else {
            ids.remove(providerId)
        }
        defaults.set(ids.sorted(), forKey: key)
    }
}

@MainActor
@Observable
final class ActivityDetectionModel {
    private let registry: ProviderRegistry
    private let errorLog: ErrorLog

    /// Each dictionary is reassigned as a whole value so @Observable notifies observers.
    private(set) var statuses: [String: ActivitySignalStatus] = [:]
    private(set) var errors: [String: DisplayText] = [:]
    private(set) var busyProviderIds: Set<String> = []
    private(set) var dismissedProviderIds = ActivityDetectionNoticeDismissals.providerIds

    init(registry: ProviderRegistry, errorLog: ErrorLog) {
        self.registry = registry
        self.errorLog = errorLog
    }

    /// The registry answers `nil` for a disabled provider or one without the capability.
    func refreshStatuses(for providerIds: [String]) async {
        for providerId in providerIds {
            let status = await registry.activitySignalStatus(for: providerId)
            var updated = statuses
            updated[providerId] = status
            statuses = updated
        }
    }

    func install(for providerId: String) async {
        await perform(operation: "install-activity-signal", for: providerId) {
            try await registry.installActivitySignal(for: providerId)
            setNoticeDismissed(false, for: providerId)
        }
    }

    func remove(for providerId: String) async {
        await perform(operation: "remove-activity-signal", for: providerId) {
            try await registry.removeActivitySignal(for: providerId)
        }
    }

    func dismissNotice(for providerId: String) {
        setNoticeDismissed(true, for: providerId)
    }

    func isAwaitingFirstSignal(_ providerId: String) -> Bool {
        if case .awaitingFirstSignal = statuses[providerId] {
            return true
        }
        return false
    }

    private func setNoticeDismissed(_ dismissed: Bool, for providerId: String) {
        ActivityDetectionNoticeDismissals.setDismissed(dismissed, for: providerId)
        dismissedProviderIds = ActivityDetectionNoticeDismissals.providerIds
    }

    private func perform(
        operation: String,
        for providerId: String,
        action: () async throws -> Void
    ) async {
        guard !busyProviderIds.contains(providerId) else { return }
        busyProviderIds = busyProviderIds.union([providerId])
        errors = errors.filter { $0.key != providerId }
        do {
            try await action()
        } catch {
            record(error, operation: operation, providerId: providerId)
        }
        await refreshStatuses(for: [providerId])
        busyProviderIds = busyProviderIds.subtracting([providerId])
    }

    private func record(_ error: any Error, operation: String, providerId: String) {
        guard !(error is CancellationError), error as? ProviderSetupError != .notSupported else { return }
        errorLog.record(
            component: "app",
            operation: operation,
            code: "operation-failed",
            providerID: providerId,
            error: error
        )
        var updated = errors
        updated[providerId] = DisplayText(describing: error)
        errors = updated
    }
}
