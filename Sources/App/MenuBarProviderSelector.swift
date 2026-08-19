import Core
import Foundation

enum MenuBarProviderSelector {
    static func providerId(
        configuredProviderIds: [String],
        enabledProviderIds: Set<String>,
        providerStates: [String: ProviderState],
        fastRefreshingProviderIds: Set<String>,
        isAutomatic: Bool
    ) -> String? {
        guard isAutomatic else { return configuredProviderIds.first }

        let configuredIds = Set(configuredProviderIds)
        let orderIndices = configuredOrderIndices(for: configuredProviderIds)
        let candidates = providerStates.compactMap { providerId, state -> Candidate? in
            guard configuredIds.contains(providerId),
                  enabledProviderIds.contains(providerId),
                  case let .loaded(quota) = state,
                  QuotaStatusResolver.resolve(for: quota) != .fallback
            else {
                return nil
            }
            return Candidate(
                providerId: providerId,
                lastUpdated: quota.lastUpdated,
                configuredOrderIndex: orderIndices[providerId] ?? .max
            )
        }

        guard !candidates.isEmpty else { return configuredProviderIds.first }

        let fastCandidates = candidates.filter {
            fastRefreshingProviderIds.contains($0.providerId)
        }
        if !fastCandidates.isEmpty {
            return fastCandidates.sorted(by: fastCandidatePrecedes).first?.providerId
        }

        return candidates.sorted(by: updatedCandidatePrecedes).first?.providerId
    }

    private static func configuredOrderIndices(for providerIds: [String]) -> [String: Int] {
        var indices: [String: Int] = [:]
        for (index, providerId) in providerIds.enumerated() where indices[providerId] == nil {
            indices[providerId] = index
        }
        return indices
    }

    static func fastCandidatePrecedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.configuredOrderIndex != rhs.configuredOrderIndex {
            return lhs.configuredOrderIndex < rhs.configuredOrderIndex
        }
        return lhs.providerId < rhs.providerId
    }

    static func updatedCandidatePrecedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.lastUpdated != rhs.lastUpdated {
            return lhs.lastUpdated > rhs.lastUpdated
        }
        return fastCandidatePrecedes(lhs, rhs)
    }

    struct Candidate {
        let providerId: String
        let lastUpdated: Date
        let configuredOrderIndex: Int
    }
}
