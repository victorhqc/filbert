import Core
import SwiftUI

extension QuotaViewModel {
    func providerInfo(for providerId: String) -> ProviderInfo? {
        registry.registeredProviders.first { $0.id == providerId }
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
