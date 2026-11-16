import Core
import SwiftUI

@MainActor
struct AppearanceTab: View {
    let viewModel: QuotaViewModel

    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    var body: some View {
        SettingsForm {
            menuBarSection
            panelSection
            BalanceColorsSection()
        }
        .navigationTitle(String(displayLocalized: "Appearance", bundle: .module))
    }

    private var menuBarSection: some View {
        Section {
            Picker(
                String(displayLocalized: "Icon style", bundle: .module),
                selection: Binding(
                    get: { viewModel.isVintageMacIconEnabled },
                    set: { viewModel.setVintageMacIconEnabled($0) }
                )
            ) {
                Text(String(displayLocalized: "Ring", bundle: .module)).tag(false)
                Text(String(displayLocalized: "Vintage Mac", bundle: .module)).tag(true)
            }
            .pickerStyle(.segmented)
            .help(String(
                displayLocalized: "Show a classic Happy / Sad Mac face instead of the ring in the menu bar",
                bundle: .module
            ))

            Picker(
                String(displayLocalized: "Show usage for", bundle: .module),
                selection: Binding(
                    get: { viewModel.isAutomaticMenuBarProviderSelection },
                    set: { viewModel.setAutomaticMenuBarProviderSelection($0) }
                )
            ) {
                Text(String(displayLocalized: "Most active provider", bundle: .module)).tag(true)
                Text(String(displayLocalized: "First provider in list", bundle: .module)).tag(false)
            }
            .pickerStyle(.menu)
            .accessibilityHint(automaticSelectionHint)
        } header: {
            Text(String(displayLocalized: "Menu bar", bundle: .module))
        } footer: {
            menuBarFooter
        }
    }

    @ViewBuilder
    private var menuBarFooter: some View {
        if let provider = viewModel.menuBarProviderInfo {
            SettingsCaption(String.localizedStringWithFormat(
                String(displayLocalized: "Now showing %@.", bundle: .module),
                provider.displayName
            ))
        } else {
            providersLink(String(displayLocalized: "Set up a provider in Providers.", bundle: .module))
        }
    }

    private var panelSection: some View {
        Section {
            Picker(
                String(displayLocalized: "Layout", bundle: .module),
                selection: Binding(
                    get: { viewModel.panelLayout },
                    set: { viewModel.setPanelLayout($0) }
                )
            ) {
                Text(String(displayLocalized: "Stacked", bundle: .module)).tag(PanelLayout.stacked)
                Text(String(displayLocalized: "Tabs", bundle: .module)).tag(PanelLayout.tabs)
            }
            .pickerStyle(.segmented)

            LabeledContent(String(displayLocalized: "Provider order", bundle: .module)) {
                providersLink(String(displayLocalized: "Change in Providers", bundle: .module))
            }
        } header: {
            Text(String(displayLocalized: "Panel", bundle: .module))
        } footer: {
            SettingsCaption(panelLayoutDescription)
        }
    }

    private var panelLayoutDescription: String {
        switch viewModel.panelLayout {
        case .stacked:
            String(displayLocalized: "Show every provider as a card.", bundle: .module)
        case .tabs:
            String(displayLocalized: "Show one provider at a time. Select a tab to see its details.", bundle: .module)
        }
    }

    private var automaticSelectionHint: String {
        guard let provider = viewModel.menuBarProviderInfo else {
            return String(displayLocalized: "Automatic selection description", bundle: .module)
        }
        return String.localizedStringWithFormat(
            String(displayLocalized: "Automatic selection accessibility hint", bundle: .module),
            provider.displayName
        )
    }

    private func providersLink(_ title: String) -> some View {
        Button {
            navigation?.open(SettingsDestination(tab: .providers))
        } label: {
            Label(title, systemImage: "arrow.right.circle")
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}

@MainActor
private struct BalanceColorsSection: View {
    @State private var lowInput: Double = BalanceThresholds.low
    @State private var okInput: Double = BalanceThresholds.ok
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            lowStepper
            okStepper
            tierPreview
        } header: {
            Text(String(displayLocalized: "Balance colors", bundle: .module))
        } footer: {
            SettingsCaption(String(
                displayLocalized: "Applies to every provider currency (USD, CNY, …).",
                bundle: .module
            ))
        }
    }

    private var lowStepper: some View {
        stepperRow(
            label: String(displayLocalized: "Low below", bundle: .module),
            value: $lowInput,
            range: 0 ... 1000
        )
        .onChange(of: lowInput) { _, newLow in
            if okInput <= newLow {
                okInput = newLow + 1
            }
            persist()
        }
    }

    private var okStepper: some View {
        stepperRow(
            label: String(displayLocalized: "OK at or above", bundle: .module),
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

    private var tierPreview: some View {
        let lowInt = Int(lowInput)
        let okInt = Int(okInput)
        return HStack(spacing: 16) {
            swatchRow(
                color: ProviderVisualStyle.tierColor(.critical, scheme: colorScheme),
                caption: String(displayLocalized: "under \(lowInt)", bundle: .module)
            )
            swatchRow(
                color: ProviderVisualStyle.tierColor(.warn, scheme: colorScheme),
                caption: "\(lowInt)–\(okInt)"
            )
            swatchRow(
                color: ProviderVisualStyle.tierColor(.good, scheme: colorScheme),
                caption: String(displayLocalized: "\(okInt) and up", bundle: .module)
            )
        }
        .accessibilityElement(children: .combine)
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

    private func persist() {
        BalanceThresholds.set(low: lowInput, ok: okInput)
    }
}
