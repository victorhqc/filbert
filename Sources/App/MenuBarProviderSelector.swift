import Core

enum MenuBarProviderSelector {
    static func providerId(
        configuredProviderIds: [String],
        enabledProviderIds: Set<String>,
        providerStates: [String: ProviderState],
        effectiveActivityScores: [String: Double],
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
                effectiveActivityScore: effectiveActivityScores[providerId] ?? 0,
                configuredOrderIndex: orderIndices[providerId] ?? .max
            )
        }

        guard !candidates.isEmpty else { return configuredProviderIds.first }

        return candidates.sorted(by: candidatePrecedes).first?.providerId
    }

    private static func configuredOrderIndices(for providerIds: [String]) -> [String: Int] {
        var indices: [String: Int] = [:]
        for (index, providerId) in providerIds.enumerated() where indices[providerId] == nil {
            indices[providerId] = index
        }
        return indices
    }

    static func candidatePrecedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.effectiveActivityScore != rhs.effectiveActivityScore {
            return lhs.effectiveActivityScore > rhs.effectiveActivityScore
        }
        if lhs.configuredOrderIndex != rhs.configuredOrderIndex {
            return lhs.configuredOrderIndex < rhs.configuredOrderIndex
        }
        return lhs.providerId < rhs.providerId
    }

    struct Candidate {
        let providerId: String
        let effectiveActivityScore: Double
        let configuredOrderIndex: Int
    }
}
