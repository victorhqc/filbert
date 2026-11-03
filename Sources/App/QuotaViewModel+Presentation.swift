import Core
import SwiftUI

extension QuotaViewModel {
    func providerInfo(for providerId: String) -> ProviderInfo? {
        registry.registeredProviders.first { $0.id == providerId }
    }

    var menuBarProviderId: String? {
        MenuBarProviderSelector.providerId(
            configuredProviderIds: configuredProviderIds,
            enabledProviderIds: enabledProviderIds,
            providerStates: providerStates,
            effectiveActivityScores: effectiveActivityScores,
            isAutomatic: isAutomaticMenuBarProviderSelection
        )
    }

    var menuBarProviderInfo: ProviderInfo? {
        guard let menuBarProviderId else { return nil }
        return providerInfo(for: menuBarProviderId)
    }

    func setAutomaticMenuBarProviderSelection(_ isAutomatic: Bool) {
        guard isAutomaticMenuBarProviderSelection != isAutomatic else { return }
        MenuBarProviderSelectionPreferences.isAutomatic = isAutomatic
        isAutomaticMenuBarProviderSelection = isAutomatic
        rescheduleActivityExpiration()
    }

    func setVintageMacIconEnabled(_ isEnabled: Bool) {
        guard isVintageMacIconEnabled != isEnabled else { return }
        VintageMacIcon.setEnabled(isEnabled)
        isVintageMacIconEnabled = isEnabled
    }

    var panelLayout: PanelLayout {
        panel.layout
    }

    func setPanelLayout(_ layout: PanelLayout) {
        guard panel.layout != layout else { return }
        PanelLayoutPreferences.setLayout(layout)
        panel.layout = layout
    }

    var selectedTabProviderId: String? {
        Self.resolvedSelectedTab(saved: panel.savedSelectedTabProviderId, configured: configuredProviderIds)
    }

    func selectTab(_ providerId: String) {
        guard panel.savedSelectedTabProviderId != providerId else { return }
        PanelLayoutPreferences.setSelectedTabProviderId(providerId)
        panel.savedSelectedTabProviderId = providerId
    }

    static func resolvedSelectedTab(saved: String?, configured: [String]) -> String? {
        guard let saved, configured.contains(saved) else { return configured.first }
        return saved
    }

    func isCollapsed(_ providerId: String) -> Bool {
        _ = collapseStateRevision
        return Self.resolvedCollapseState(
            providerId: providerId,
            topProviderId: configuredProviderIds.first,
            savedState: ProviderCollapseState.collapsedState(for: providerId)
        )
    }

    func toggleCollapsed(_ providerId: String) {
        ProviderCollapseState.setCollapsed(!isCollapsed(providerId), for: providerId)
        collapseStateRevision += 1
    }

    static func resolvedCollapseState(
        providerId: String,
        topProviderId: String?,
        savedState: Bool?
    ) -> Bool {
        savedState ?? (providerId != topProviderId)
    }

    func moveProvider(from source: IndexSet, to destination: Int) {
        var ids = orderedProviderIds
        ids.move(fromOffsets: source, toOffset: destination)
        ProviderOrder.setOrder(ids)
        orderedProviderIds = ids
        refreshDerived()
    }

    func persistOrder(_ ids: [String]) {
        ProviderOrder.setOrder(ids)
        orderedProviderIds = ids
        refreshDerived()
    }

    func recomputeOrderedProviderIds() {
        let sortedByName = registry.registeredProviders.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        orderedProviderIds = ProviderOrder.effectiveOrder(for: sortedByName.map(\.id))
    }
}

struct PanelPresentation {
    var layout = PanelLayoutPreferences.layout
    var savedSelectedTabProviderId = PanelLayoutPreferences.selectedTabProviderId
}
