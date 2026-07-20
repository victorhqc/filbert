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
                overrideURL: viewModel.overrideURL(for: provider.id),
                onSaveKey: { key in
                    try? viewModel.saveKey(key, for: provider.id)
                },
                onClearKey: {
                    try? viewModel.deleteKey(for: provider.id)
                },
                onSaveOverride: { url in
                    try viewModel.saveOverrideURL(url, for: provider.id)
                }
            )
        }
        .navigationTitle(String(localized: "Providers"))
        .onAppear {
            // MenuBarExtra apps run as accessory apps and don't grab focus by
            // default; without this, the Settings window can appear behind
            // whatever app was previously frontmost.
            NSApp.activate(ignoringOtherApps: true)
        }
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
    let overrideURL: URL?
    let onSaveKey: (String) -> Void
    let onClearKey: () -> Void
    /// Saves (or clears) the base-URL override. Throws `ProviderOverrideError`
    /// on invalid input so the row can surface an inline error (ui 03 AC3).
    let onSaveOverride: (URL?) throws -> Void

    @State private var apiKey: String = ""
    // Advanced disclosure state (ui 03 AC1).
    @State private var advancedExpanded: Bool = false
    @State private var overrideInput: String = ""
    @State private var overrideErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if isConfigured {
                Button(String(localized: "Clear Key")) {
                    onClearKey()
                }
                .font(.caption)
            } else {
                HStack(spacing: 6) {
                    SecureField(String(localized: "API Key"), text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveKeyIfValid() }

                    Button(String(localized: "Save")) {
                        saveKeyIfValid()
                    }
                    .disabled(apiKey.isEmpty)
                }
            }

            advancedDisclosure
        }
        .padding(.vertical, 4)
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline)
                Text(provider.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            badge

            // Collapsed indicator when a proxy override is active (ui 03 AC5).
            if overrideURL != nil {
                Text(String(localized: "custom URL"))
                    .font(.caption.monospaced())
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.15))
                    )
            }
        }
    }

    private var badge: some View {
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

    private var advancedDisclosure: some View {
        // A Button-driven toggle instead of `DisclosureGroup`. On macOS,
        // `DisclosureGroup` inside a `List` row has its tap intercepted by
        // the List's row-selection behavior, leaving the label visually
        // inert. Driving the expand state from our own Button makes the tap
        // target deterministic.
        //
        // No explicit animation: animating the height change inside a List
        // row desyncs the List's scroll geometry and produces a render
        // artifact (garbled row + flickering scrollbar) that only resolves
        // when the user clicks into the row. The instant toggle lets the
        // List re-tile cleanly.
        VStack(alignment: .leading, spacing: 6) {
            Button {
                advancedExpanded.toggle()
                if advancedExpanded {
                    refreshOverrideInput()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Advanced"))
                    Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                overrideEditor
            }
        }
    }

    private var overrideEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Read-only default, so the user knows what they'd be overriding (ui 03 AC2).
            HStack(spacing: 4) {
                Text(String(localized: "Default:"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(provider.defaultBaseURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                TextField(
                    String(localized: "Custom base URL (proxy)"),
                    text: $overrideInput
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveOverride() }
                .onChange(of: overrideInput) { _, _ in
                    // AC3: clear the error as soon as the user edits.
                    if overrideErrorMessage != nil {
                        overrideErrorMessage = nil
                    }
                }

                Button(String(localized: "Save")) {
                    saveOverride()
                }
                Button(String(localized: "Reset")) {
                    resetOverride()
                }
                .disabled(overrideURL == nil)
            }

            if let overrideErrorMessage {
                Text(overrideErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 2)
    }

    private func saveKeyIfValid() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSaveKey(trimmed)
        apiKey = ""
    }

    private func saveOverride() {
        let trimmed = overrideInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmed.isEmpty ? nil : URL(string: trimmed)
        // If the user typed something that doesn't even parse as a URL,
        // surface the same invalidURL error Core would for a bad scheme.
        let resolved: URL?
        if trimmed.isEmpty {
            resolved = nil
        } else if let url {
            resolved = url
        } else {
            overrideErrorMessage = String(localized: "Only https URLs are allowed.")
            return
        }

        do {
            try onSaveOverride(resolved)
            overrideErrorMessage = nil
        } catch {
            overrideErrorMessage = String(localized: "Only https URLs are allowed.")
        }
    }

    private func resetOverride() {
        do {
            try onSaveOverride(nil)
            overrideInput = ""
            overrideErrorMessage = nil
        } catch {
            overrideErrorMessage = String(localized: "Only https URLs are allowed.")
        }
    }

    /// Re-syncs the input field with the stored value when the disclosure
    /// expands, so the field never shows stale text after an external change.
    private func refreshOverrideInput() {
        overrideInput = overrideURL?.absoluteString ?? ""
        overrideErrorMessage = nil
    }
}
