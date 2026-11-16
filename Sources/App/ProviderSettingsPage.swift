import Core
import SwiftUI

@MainActor
struct ProviderSettingsPage: View {
    static let activityDetectionRowId = "activity-detection"

    let viewModel: QuotaViewModel
    let provider: ProviderInfo
    let navigation: SettingsNavigation

    @AccessibilityFocusState private var isActivityDetectionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            SettingsForm {
                header

                if isEnabled {
                    ProviderConnectionSection(viewModel: viewModel, provider: provider)
                    ProviderUsageChecksSection(
                        viewModel: viewModel,
                        provider: provider,
                        isActivityDetectionFocused: $isActivityDetectionFocused
                    )
                    if case .apiKey = provider.authShape {
                        advancedSection
                    }
                    if let disclaimer = provider.disclaimer {
                        Section {
                            Label(disclaimer, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Section {
                        SettingsCaption(String.localizedStringWithFormat(
                            String(
                                displayLocalized: "Turn on %@ to track its usage. Filbert keeps its saved settings.",
                                bundle: .module
                            ),
                            provider.displayName
                        ))
                    }
                }
            }
            .onChange(of: navigation.pendingAnchor, initial: true) {
                reveal(using: proxy)
            }
        }
        .task {
            await viewModel.activityDetection.refreshStatuses(for: [provider.id])
        }
    }

    private var isEnabled: Bool {
        viewModel.isEnabled(provider.id)
    }

    private var header: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                ProviderLogoBadge(glyph: provider.glyph)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.headline)
                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(
                    trackLabel,
                    isOn: Binding(
                        get: { isEnabled },
                        set: { viewModel.setProviderEnabled($0, for: provider.id) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .help(trackLabel)
            }
        }
    }

    private var trackLabel: String {
        String.localizedStringWithFormat(
            String(displayLocalized: "Track %@", bundle: .module),
            provider.displayName
        )
    }

    private var advancedSection: some View {
        let overrideURL = viewModel.overrideURL(for: provider.id)
        return Section {
            DisclosureGroup {
                BaseURLOverrideEditor(
                    provider: provider,
                    overrideURL: overrideURL,
                    errorLog: viewModel.errorLog,
                    onSave: { url in try viewModel.saveOverrideURL(url, for: provider.id) }
                )
                .padding(.vertical, 4)
            } label: {
                HStack(spacing: 8) {
                    Text(String(displayLocalized: "Advanced", bundle: .module))
                    if overrideURL != nil {
                        Text(String(displayLocalized: "custom URL", bundle: .module))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private func reveal(using proxy: ScrollViewProxy) {
        guard navigation.pendingAnchor == .activityDetection,
              navigation.selectedProviderId == provider.id
        else {
            return
        }
        _ = navigation.takePendingAnchor()
        Task {
            await viewModel.activityDetection.refreshStatuses(for: [provider.id])
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                proxy.scrollTo(Self.activityDetectionRowId, anchor: .center)
            }
            isActivityDetectionFocused = true
        }
    }
}
