import Core
import SwiftUI

@MainActor
struct ProvidersSettingsTab: View {
    private static let highlightDuration = Duration.seconds(1.6)

    let viewModel: QuotaViewModel
    let navigation: SettingsNavigation

    @State private var highlightedProviderId: String?
    @AccessibilityFocusState private var focusedActivitySection: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            SettingsScrollColumn {
                ForEach(viewModel.registeredProvidersOrdered) { provider in
                    ProviderSetupCard(
                        viewModel: viewModel,
                        provider: provider,
                        isHighlighted: highlightedProviderId == provider.id
                    ) {
                        ActivityDetectionSection(
                            viewModel: viewModel,
                            provider: provider,
                            focus: $focusedActivitySection
                        )
                    }
                    .id(provider.id)
                }
            }
            .onChange(of: navigation.pendingProviderId, initial: true) {
                reveal(using: proxy)
            }
        }
        .background(WindowKeyObserver {
            Task { await refreshStatuses() }
        })
        .navigationTitle(String(displayLocalized: "Providers", bundle: .module))
    }

    private func refreshStatuses() async {
        await viewModel.activityDetection.refreshStatuses(for: viewModel.registeredProvidersOrdered.map(\.id))
    }

    private func reveal(using proxy: ScrollViewProxy) {
        guard let providerId = navigation.takePendingProviderId() else { return }
        Task {
            await viewModel.activityDetection.refreshStatuses(for: [providerId])
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                proxy.scrollTo(providerId, anchor: .top)
            }
            highlightedProviderId = providerId
            focusedActivitySection = providerId
            try? await Task.sleep(for: Self.highlightDuration)
            guard highlightedProviderId == providerId else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                highlightedProviderId = nil
            }
        }
    }
}
