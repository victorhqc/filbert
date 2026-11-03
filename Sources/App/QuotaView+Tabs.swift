import Core
import SwiftUI

extension QuotaView {
    @ViewBuilder
    var tabbedProviders: some View {
        let selectedId = viewModel.selectedTabProviderId

        ProviderTabFlowLayout(spacing: 4) {
            ForEach(viewModel.configuredProviderIds, id: \.self) { providerId in
                providerTab(providerId: providerId, isSelected: providerId == selectedId)
            }
        }

        if let selectedId {
            selectedProviderCard(providerId: selectedId)
        }
    }

    @ViewBuilder
    private func providerTab(providerId: String, isSelected: Bool) -> some View {
        if let info = viewModel.providerInfo(for: providerId), let state = viewModel.providerStates[providerId] {
            ProviderTab(
                info: info,
                state: state,
                errorMessage: viewModel.headerErrorMessage(providerId: providerId, state: state),
                isSelected: isSelected,
                accessibilityLabel: headerAccessibilityLabel(
                    info: info,
                    state: state,
                    collapsed: true,
                    fastRefreshStatus: fastRefreshStatus(for: providerId)
                ),
                onSelect: { viewModel.selectTab(providerId) }
            )
        }
    }

    @ViewBuilder
    private func selectedProviderCard(providerId: String) -> some View {
        if let info = viewModel.providerInfo(for: providerId), let state = viewModel.providerStates[providerId] {
            providerCard(providerId: providerId, state: state, showsBody: true) {
                HStack(spacing: 6) {
                    providerTitle(info: info, fastRefreshStatus: fastRefreshStatus(for: providerId))
                    Spacer(minLength: 4)
                    headerTrailingControls(providerId: providerId, state: state)
                }
            }
        }
    }
}
