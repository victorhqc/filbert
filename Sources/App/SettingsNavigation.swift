import Observation

struct SettingsDestination: Equatable {
    let tab: SettingsTab
    let providerId: String?

    init(tab: SettingsTab, providerId: String? = nil) {
        self.tab = tab
        self.providerId = providerId
    }
}

/// Lives above the language rebuild, so a language change keeps the open tab.
@MainActor
@Observable
final class SettingsNavigation {
    var selectedTab: SettingsTab = .general

    /// Kept until the providers list takes it, because on first open Settings
    /// builds its views after the destination is set.
    private(set) var pendingProviderId: String?

    func open(_ destination: SettingsDestination) {
        selectedTab = destination.tab
        pendingProviderId = destination.providerId
    }

    func takePendingProviderId() -> String? {
        defer { pendingProviderId = nil }
        return pendingProviderId
    }
}
