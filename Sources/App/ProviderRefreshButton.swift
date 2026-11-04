import Core
import SwiftUI

@MainActor
struct ProviderRefreshButton: View {
    let viewModel: QuotaViewModel
    let providerId: String
    let state: ProviderState

    var body: some View {
        let defaultHelp = String(displayLocalized: "Check usage now", bundle: .module)
        Button {
            viewModel.manualRefresh(for: providerId)
        } label: {
            RefreshIcon(isRefreshing: viewModel.isRefreshing[providerId] ?? false)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .help(viewModel.refreshHelp(for: providerId, defaultHelp: defaultHelp))
        .accessibilityLabel(defaultHelp)
        .disabled(isDisabled)
    }

    private var isDisabled: Bool {
        if viewModel.isRefreshing[providerId] == true {
            return true
        }
        if case .loading = state {
            return true
        }
        return viewModel.manualRefreshWaitRemaining(for: providerId) != nil
    }
}

extension QuotaViewModel {
    func refreshHelp(for providerId: String, defaultHelp: String) -> String {
        guard let remaining = manualRefreshWaitRemaining(for: providerId) else {
            return defaultHelp
        }
        let wholeMinutes = max((remaining / 60).rounded(.up), 1) * 60
        let duration = CoarseDurationFormatting.string(from: wholeMinutes, unitsStyle: .full)
        return String(
            displayLocalized: "The provider asked Filbert to wait. Try again in \(duration).",
            bundle: .module
        )
    }

    func headerErrorMessage(providerId: String, state: ProviderState) -> String? {
        if let refreshError = refreshErrors[providerId] {
            return refreshError.resolved
        }
        if case let .error(message) = state {
            return message.resolved
        }
        return nil
    }
}
