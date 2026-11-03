import Core
import SwiftUI

@MainActor
struct ProviderTab: View {
    let viewModel: QuotaViewModel
    let info: ProviderInfo
    let state: ProviderState
    let isSelected: Bool
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.selectTab(info.id)
            } label: {
                selectLabel
            }
            .buttonStyle(.plain)
            .help(info.displayName)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            ProviderRefreshButton(viewModel: viewModel, providerId: info.id, state: state)
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor.opacity(0.18) : ProviderVisualStyle.neutralContainerFill,
            in: RoundedRectangle(cornerRadius: ProviderVisualStyle.cardCornerRadius)
        )
    }

    private var selectLabel: some View {
        HStack(spacing: 4) {
            ProviderLogoBadge(glyph: info.glyph)

            if let tabLabel = info.tabLabel {
                Text(tabLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }

            status
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let message = viewModel.headerErrorMessage(providerId: info.id, state: state) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption2)
                    .help(message)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case let .loaded(quota):
            CompactProviderStatus(quota: quota)
        case .loading:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
        case .unconfigured, .setup, .error:
            EmptyView()
        }
    }
}
