import AppKit
import Core
import SwiftUI

@MainActor
struct WelcomeView: View {
    let flow: WelcomeFlow
    let viewModel: QuotaViewModel
    let sleepPrevention: SleepPreventionController
    let launchAtLogin: LaunchAtLoginController
    let displayLanguage: DisplayLanguageModel
    let onStatusItemCheck: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                stepContent
                    .padding(.horizontal, 32)
                    .padding(.top, 36)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
            }
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 540, height: 540)
        .background(WindowTitle(String(displayLocalized: "Welcome to Filbert", bundle: .module)))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .introduction:
            introductionStep
        case .provider:
            providerStep
        case .menuBar:
            menuBarStep
        }
    }

    // MARK: - Introduction

    private var introductionStep: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            heading(String(displayLocalized: "Welcome to Filbert", bundle: .module))

            Text(String(
                displayLocalized: "Filbert shows how much of your AI usage is left before you hit a limit.",
                bundle: .module
            ))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SettingsCard(
                heading: String(displayLocalized: "Language", bundle: .module),
                description: String(displayLocalized: "Choose the language Filbert uses.", bundle: .module)
            ) {
                LanguagePicker(displayLanguage: displayLanguage)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Provider

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(String(displayLocalized: "Connect a provider", bundle: .module))

            Text(String(
                displayLocalized: "Choose an AI provider you use. You can add more later in Settings.",
                bundle: .module
            ))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.registeredProvidersOrdered) { provider in
                if flow.selectedProviderId == provider.id {
                    ProviderSetupCard(viewModel: viewModel, provider: provider)
                } else {
                    providerRow(provider)
                }
            }
        }
    }

    private func providerRow(_ provider: ProviderInfo) -> some View {
        Button {
            flow.selectedProviderId = provider.id
        } label: {
            SettingsCard {
                HStack(spacing: 10) {
                    ProviderLogoBadge(glyph: provider.glyph)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(.headline)
                        Text(provider.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if viewModel.configuredProviderIds.contains(provider.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel(String(displayLocalized: "Configured", bundle: .module))
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Menu bar

    private var menuBarStep: some View {
        VStack(spacing: 16) {
            heading(String(displayLocalized: "Filbert lives in your menu bar", bundle: .module))

            MenuBarIllustration(viewModel: viewModel, sleepPrevention: sleepPrevention)
                .padding(.vertical, 8)

            VStack(spacing: 6) {
                Text(String(displayLocalized: "Click its icon to see your usage.", bundle: .module))
                Text(String(displayLocalized: "Filbert has no Dock icon and no main window.", bundle: .module))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if flow.isStatusItemVisible != true {
                hiddenIconHelp(isConfirmedHidden: flow.isStatusItemVisible == false)
            }

            SettingsCard(
                heading: String(displayLocalized: "Startup", bundle: .module),
                description: String(
                    displayLocalized: "Start Filbert in the menu bar after you sign in to your Mac.",
                    bundle: .module
                )
            ) {
                LaunchAtLoginControls(launchAtLogin: launchAtLogin)
            }
        }
        .onAppear {
            launchAtLogin.refreshStatus()
            onStatusItemCheck()
        }
    }

    private func hiddenIconHelp(isConfirmedHidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(displayLocalized: "Can't see the icon? The menu bar may be full.", bundle: .module))
            Text(String(
                displayLocalized: "Hold ⌘ and drag other icons out of the menu bar to make room.",
                bundle: .module
            ))
        }
        .font(isConfirmedHidden ? .callout : .caption)
        .foregroundStyle(isConfirmedHidden ? .primary : .secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isConfirmedHidden ? 12 : 0)
        .background {
            if isConfirmedHidden {
                RoundedRectangle(cornerRadius: ProviderVisualStyle.cardCornerRadius)
                    .fill(Color.orange.opacity(0.14))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(String(
                displayLocalized: "Step \(flow.step.number) of \(WelcomeStep.allCases.count)",
                bundle: .module
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if !flow.isFirstStep {
                Button(String(displayLocalized: "Back", bundle: .module)) {
                    flow.goBack()
                }
            }

            Button(primaryButtonTitle) {
                if flow.isLastStep {
                    onFinish()
                } else {
                    flow.goForward()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private var primaryButtonTitle: String {
        switch flow.step {
        case .introduction:
            String(displayLocalized: "Continue", bundle: .module)
        case .provider where viewModel.hasAnyConfiguredProvider:
            String(displayLocalized: "Continue", bundle: .module)
        case .provider:
            String(displayLocalized: "Skip for now", bundle: .module)
        case .menuBar:
            String(displayLocalized: "Done", bundle: .module)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.title.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private struct MenuBarIllustration: View {
    let viewModel: QuotaViewModel
    let sleepPrevention: SleepPreventionController

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo")
            Spacer()
            filbertIcon
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "magnifyingglass")
            Image(systemName: "switch.2")
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .frame(width: 400, height: 28)
        .background(.bar, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .padding(.bottom, 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(displayLocalized: "A menu bar with the Filbert icon marked", bundle: .module))
    }

    private var filbertIcon: some View {
        MenuBarStatusIcon(viewModel: viewModel, sleepPrevention: sleepPrevention)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
            .overlay(alignment: .bottom) {
                Image(systemName: "arrowtriangle.up.fill")
                    .foregroundStyle(Color.accentColor)
                    .offset(y: 24)
            }
    }
}

/// An `NSHostingController` in a plain `NSWindow` ignores `navigationTitle`. The title is hidden
/// but still names the window for VoiceOver and Mission Control.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    func makeNSView(context _: Context) -> TitleApplyingView {
        TitleApplyingView(title: title)
    }

    func updateNSView(_ view: TitleApplyingView, context _: Context) {
        view.title = title
    }
}

private final class TitleApplyingView: NSView {
    var title: String {
        didSet { window?.title = title }
    }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.title = title
    }
}
