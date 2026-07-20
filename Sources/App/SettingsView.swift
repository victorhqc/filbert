import Core
import SwiftUI

// MARK: - Settings scene content (AC2: provider list (ui 02))

@MainActor
struct SettingsView: View {
    let viewModel: QuotaViewModel

    var body: some View {
        List(viewModel.registeredProvidersSorted) { provider in
            ProviderSettingsRow(
                provider: provider,
                isConfigured: viewModelIsConfigured(provider.id),
                onSave: { key in
                    try? viewModel.saveKey(key, for: provider.id)
                },
                onClear: {
                    try? viewModel.deleteKey(for: provider.id)
                }
            )
        }
        .navigationTitle(String(localized: "Providers"))
    }

    private func viewModelIsConfigured(_ providerId: String) -> Bool {
        if case .unconfigured = viewModel.providerStates[providerId] {
            return false
        }
        return true
    }
}

// MARK: - Per-provider row (AC3/AC4: configured badge or key entry (ui 02))

@MainActor
private struct ProviderSettingsRow: View {
    let provider: ProviderInfo
    let isConfigured: Bool
    let onSave: (String) -> Void
    let onClear: () -> Void

    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.headline)
                    Text(provider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isConfigured {
                    Text(String(localized: "Configured"))
                        .font(.caption.monospaced())
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green.opacity(0.15))
                        )
                } else {
                    Text(String(localized: "Unconfigured"))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
            }

            if isConfigured {
                Button(String(localized: "Clear Key")) {
                    onClear()
                }
                .font(.caption)
            } else {
                HStack(spacing: 6) {
                    SecureField(String(localized: "API Key"), text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveIfValid() }

                    Button(String(localized: "Save")) {
                        saveIfValid()
                    }
                    .disabled(apiKey.isEmpty)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func saveIfValid() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        apiKey = ""
    }
}
