import AppKit
import Core
import SwiftUI

// MARK: - Settings scene content (AC1: tabbed layout (ui 09))

@MainActor
struct SettingsView: View {
    let viewModel: QuotaViewModel

    var body: some View {
        TabView {
            // AC1: credentials and per-provider settings stay here (ui 02/03/05/08).
            providersTab
                .tabItem {
                    Label(String(localized: "Providers"), systemImage: "key.fill")
                }

            // AC1: ordering lives on its own tab so credentials never mix
            // with appearance settings (ui 09).
            AppearanceTab(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Appearance"), systemImage: "list.bullet.indent")
                }
        }
        .onAppear {
            // MenuBarExtra apps run as accessory apps and don't grab focus by
            // default; without this, the Settings window can appear behind
            // whatever app was previously frontmost.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Tab 1 — provider credentials, base-URL overrides, and balance
    /// thresholds. Content is unchanged from (ui 02/03/05/08); only nested
    /// under the tab (ui 09 AC1).
    private var providersTab: some View {
        List {
            ForEach(viewModel.registeredProvidersOrdered) { provider in
                switch provider.authShape {
                case .apiKey:
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
                case .apiKeyFree:
                    APIKeyFreeSettingsRow(
                        provider: provider,
                        state: viewModel.providerStates[provider.id] ?? .unconfigured,
                        canInstall: viewModel.canInstallHelper(for: provider.id),
                        onInstall: {
                            Task { await viewModel.installHelper(for: provider.id) }
                        },
                        onRemove: {
                            Task { await viewModel.removeHelper(for: provider.id) }
                        }
                    )
                }
            }
        }
        .navigationTitle(String(localized: "Providers"))
    }

    private func viewModelIsConfigured(_ providerId: String) -> Bool {
        guard let state = viewModel.providerStates[providerId] else { return false }
        switch state {
        case .unconfigured, .setup:
            return false
        case .loading, .loaded, .error:
            return true
        }
    }
}

// MARK: - Appearance tab (AC2/AC3: provider ordering (ui 09))

@MainActor
private struct AppearanceTab: View {
    let viewModel: QuotaViewModel
    @State private var isVintageMacEnabled = VintageMacIcon.isEnabled

    var body: some View {
        List {
            // AC2/AC3: a lightweight caption labels the reorderable list
            // without the ~115px grouped-section header that SwiftUI would
            // otherwise reserve for a Section header (ui 11).
            Text(String(localized: "Provider order"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0))
                .listRowSeparator(.hidden)
                .moveDisabled(true)

            // AC2: one row per registered provider, display name only.
            // AC3: tight row content spacing so the order list doesn't read as
            // over-spaced next to the thresholds section below (ui 11).
            ForEach(viewModel.registeredProvidersOrdered) { provider in
                Text(provider.displayName)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            }
            .onMove { source, destination in
                // AC3: drag-and-drop re-order. The view model persists the
                // new order and refreshes derived state so the popover
                // re-renders live (ui 09 AC7).
                viewModel.moveProvider(from: source, to: destination)
            }

            // AC2: Balance thresholds relocated from the Providers tab (ui 08 AC4).
            // Contents, stepper semantics, and persistence are unchanged.
            Section {
                BalanceThresholdsSettingsRow()
            } header: {
                Text(String(localized: "Balance thresholds"))
            }

            Section {
                Toggle(isOn: $isVintageMacEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Vintage Mac"))
                        Text(vintageMacSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: isVintageMacEnabled) { _, isEnabled in
                    VintageMacIcon.setEnabled(isEnabled)
                }
            }
        }
        .navigationTitle(String(localized: "Appearance"))
    }

    private var vintageMacSubtitle: String {
        String(
            localized: "Show a classic Happy / Sad Mac face instead of the ring in the menu bar"
        )
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

// MARK: - API-key-free provider row (ui 05 AC2–AC7)

/// Settings row for `.apiKeyFree` providers (today: Claude Code). Replaces the
/// API-key field and Advanced disclosure with an install/remove control for the
/// provider's local helper, and surfaces setup state through the same badge
/// conventions used by `.apiKey` rows (ui 05 AC2).
@MainActor
private struct APIKeyFreeSettingsRow: View {
    let provider: ProviderInfo
    let state: ProviderState
    let canInstall: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            switch state {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "Working…"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case let .setup(reason):
                if canInstall {
                    // AC4: binary present, helper not installed.
                    installPromptView(reason: reason)
                } else {
                    // AC3: binary missing — show actionable message, no button.
                    setupReasonView(reason: reason)
                }
            case .loaded:
                // AC5: helper installed.
                removeHelperView
            case let .error(message):
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            case .unconfigured:
                Text(String(localized: "Not configured"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header (ui 05 AC2)

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
        }
    }

    private var badge: some View {
        switch state {
        case .loaded:
            Text(String(localized: "Ready"))
                .font(.caption.monospaced())
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.15))
                )
        case .setup:
            Text(String(localized: "Setup needed"))
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                )
        case .loading:
            Text(String(localized: "Working…"))
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                )
        case .error:
            Text(String(localized: "Error"))
                .font(.caption.monospaced())
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.15))
                )
        case .unconfigured:
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

    // MARK: - Install prompt (ui 05 AC4)

    private func installPromptView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            setupReasonView(reason: reason)

            Text(String(localized: "AI Usage reads your Claude Code usage by hooking into its status line."))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(localized: "This adds a small helper script to ~/.claude/."))
                .font(.caption)
                .foregroundColor(.secondary)

            Button(String(localized: "Install Helper")) {
                onInstall()
            }
        }
    }

    private func setupReasonView(reason: String) -> some View {
        HStack(spacing: 6) {
            if let setupHelp = provider.setupHelp {
                Button {
                    NSWorkspace.shared.open(setupHelp.url)
                } label: {
                    Label(setupHelp.linkLabel, systemImage: "arrow.up.right")
                }
                .font(.caption)
                .buttonStyle(.link)
                .layoutPriority(1)
            }

            Text(reason)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Remove helper (ui 05 AC5)

    private var removeHelperView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Helper installed and active."))
                .font(.caption)
                .foregroundColor(.secondary)

            Button(String(localized: "Remove Helper")) {
                onRemove()
            }
        }
    }
}

// MARK: - Balance thresholds section (ui 08 AC4)

/// Settings row exposing the user-configurable low/ok balance thresholds.
/// The stepper lower bound for "OK above" tracks the current "Low below" so
/// the user cannot enter an impossible pairing from the UI; `BalanceThresholds.set`
/// additionally clamps on write as a safety net (ui 08 AC2).
@MainActor
private struct BalanceThresholdsSettingsRow: View {
    @State private var lowInput: Double = BalanceThresholds.low
    @State private var okInput: Double = BalanceThresholds.ok

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            lowStepper
            okStepper
            tierPreview
            hint
        }
        .padding(.vertical, 4)
    }

    // MARK: - Steppers

    private var lowStepper: some View {
        stepperRow(
            label: String(localized: "Low below"),
            value: $lowInput,
            range: 0 ... 1000
        )
        .onChange(of: lowInput) { _, newLow in
            // Keep ok strictly above low; otherwise the ok stepper's lower
            // bound would be below its current value, which SwiftUI clamps
            // silently and the two inputs could drift apart.
            if okInput <= newLow {
                okInput = newLow + 1
            }
            persist()
        }
    }

    private var okStepper: some View {
        stepperRow(
            label: String(localized: "OK above"),
            value: $okInput,
            range: (lowInput + 1) ... 1000
        )
        .onChange(of: okInput) { _, _ in
            persist()
        }
    }

    private func stepperRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        Stepper(value: value, in: range, step: 1) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue, format: .number)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Tier preview (ui 08 AC4)

    /// Three Circle swatches matching the popover's balance-row indicator,
    /// with captions showing the resulting ranges. Uses the same Circle size
    /// as the popover so Settings and popover stay visually identical.
    private var tierPreview: some View {
        let lowInt = Int(lowInput)
        let okInt = Int(okInput)
        return VStack(alignment: .leading, spacing: 4) {
            swatchRow(color: .red, caption: String(localized: "under \(lowInt)"))
            swatchRow(color: .orange, caption: String(localized: "\(lowInt)–\(okInt)"))
            swatchRow(color: .green, caption: String(localized: "\(okInt) and up"))
        }
        .padding(.top, 2)
    }

    private func swatchRow(color: Color, caption: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Hint (ui 08 AC4)

    private var hint: some View {
        Text(String(localized: "Applies to every provider currency (USD, CNY, …)."))
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    private func persist() {
        BalanceThresholds.set(low: lowInput, ok: okInput)
    }
}
