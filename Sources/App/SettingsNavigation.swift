import Observation

enum SettingsTab: Hashable {
    case general
    case providers
    case appearance
    case about
}

enum SettingsAnchor: Equatable {
    case activityDetection
}

struct SettingsDestination: Equatable {
    let tab: SettingsTab
    let providerId: String?
    let anchor: SettingsAnchor?

    init(tab: SettingsTab, providerId: String? = nil, anchor: SettingsAnchor? = nil) {
        self.tab = tab
        self.providerId = providerId
        self.anchor = anchor
    }
}

/// Lives above the language rebuild, so a language change keeps the open tab
/// and the selected provider.
@MainActor
@Observable
final class SettingsNavigation {
    var selectedTab: SettingsTab = .general
    var selectedProviderId: String?

    /// Kept until the provider page takes it, because on first open Settings
    /// builds its views after the destination is set.
    private(set) var pendingAnchor: SettingsAnchor?

    func open(_ destination: SettingsDestination) {
        selectedTab = destination.tab
        if let providerId = destination.providerId {
            selectedProviderId = providerId
        }
        pendingAnchor = destination.anchor
    }

    func takePendingAnchor() -> SettingsAnchor? {
        defer { pendingAnchor = nil }
        return pendingAnchor
    }

    nonisolated static func resolvedProviderId(selected: String?, tracking: [String], all: [String]) -> String? {
        if let selected, all.contains(selected) {
            return selected
        }
        return tracking.first ?? all.first
    }
}
