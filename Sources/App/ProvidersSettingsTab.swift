import Core
import SwiftUI

@MainActor
struct ProvidersSettingsTab: View {
    let viewModel: QuotaViewModel
    let navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            ProviderSettingsList(viewModel: viewModel, selection: selection)
                .frame(width: 220)

            Divider()

            if let provider = selectedProvider {
                ProviderSettingsPage(viewModel: viewModel, provider: provider, navigation: navigation)
                    .id(provider.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowKeyObserver {
            Task { await refreshStatuses() }
        })
        .navigationTitle(String(displayLocalized: "Providers", bundle: .module))
    }

    private var selection: Binding<String?> {
        Binding(
            get: { resolvedProviderId },
            set: { providerId in
                guard let providerId else { return }
                navigation.selectedProviderId = providerId
            }
        )
    }

    private var resolvedProviderId: String? {
        let providers = viewModel.registeredProvidersOrdered
        return SettingsNavigation.resolvedProviderId(
            selected: navigation.selectedProviderId,
            tracking: providers.filter { viewModel.isEnabled($0.id) }.map(\.id),
            all: providers.map(\.id)
        )
    }

    private var selectedProvider: ProviderInfo? {
        guard let resolvedProviderId else { return nil }
        return viewModel.providerInfo(for: resolvedProviderId)
    }

    private func refreshStatuses() async {
        await viewModel.activityDetection.refreshStatuses(for: viewModel.registeredProvidersOrdered.map(\.id))
    }
}
