import AppKit
import Core
import SwiftUI

struct SettingsWindowConfigurator: NSViewRepresentable {
    static let minimumSize = NSSize(width: 680, height: 460)

    func makeNSView(context _: Context) -> NSView {
        SettingsWindowConfigurationView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private final class SettingsWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor [weak window] in
            // Settings applies native tab geometry after attachment, so defer the
            // style changes until that pass completes.
            try? await Task.sleep(for: .milliseconds(100))
            window?.styleMask.insert(.resizable)
            window?.contentMinSize = SettingsWindowConfigurator.minimumSize
        }
    }
}

struct SettingsCard<Content: View>: View {
    let heading: String?
    let description: String?
    @ViewBuilder let content: Content

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        heading: String? = nil,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.heading = heading
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heading {
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading)
                        .font(.headline)
                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            cardFill,
            in: RoundedRectangle(cornerRadius: ProviderVisualStyle.cardCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ProviderVisualStyle.cardCornerRadius)
                .strokeBorder(
                    Color(nsColor: .separatorColor)
                        .opacity(colorSchemeContrast == .increased ? 0.9 : 0.28),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
    }

    private var cardFill: Color {
        if reduceTransparency || colorSchemeContrast == .increased {
            Color(nsColor: .controlBackgroundColor)
        } else {
            ProviderVisualStyle.neutralContainerFill
        }
    }
}

struct SettingsCardHeader: View {
    let provider: ProviderInfo
    let status: ProviderStatusPresentation
    let isEnabled: Bool
    let onEnabledChange: @MainActor @Sendable (Bool) -> Void
    var supplementaryLabel: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderLogoBadge(glyph: provider.glyph)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(provider.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        ProviderStatusPill(status: status)
                        enablementToggle
                        if let supplementaryLabel {
                            Text(supplementaryLabel)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tint)
                        }
                    }
                }

                Text(provider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var enablementToggle: some View {
        Toggle(
            String(displayLocalized: "Enabled", bundle: .module),
            isOn: Binding(
                get: { isEnabled },
                set: { onEnabledChange($0) }
            )
        )
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityLabel(
            String.localizedStringWithFormat(
                String(displayLocalized: "Enable %@", bundle: .module),
                provider.displayName
            )
        )
        .accessibilityValue(
            isEnabled
                ? String(displayLocalized: "Enabled", bundle: .module)
                : String(displayLocalized: "Disabled", bundle: .module)
        )
    }
}

struct ProviderAccountButton: View {
    let provider: ProviderInfo
    let isEnabled: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        if isEnabled, let accountLink = provider.accountLink {
            Button {
                openURL(accountLink.url)
            } label: {
                Label(String(displayLocalized: "Go to Dashboard", bundle: .module), systemImage: "globe")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(
                String.localizedStringWithFormat(
                    String(displayLocalized: "%1$@ for %2$@", bundle: .module),
                    String(displayLocalized: "Go to Dashboard", bundle: .module),
                    provider.displayName
                )
            )
        }
    }
}

private struct ProviderStatusPill: View {
    let status: ProviderStatusPresentation

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .accessibilityHidden(true)
            Text(status.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            foregroundColor.opacity(colorSchemeContrast == .increased ? 0.22 : 0.13),
            in: Capsule()
        )
        .overlay {
            if colorSchemeContrast == .increased {
                Capsule()
                    .strokeBorder(foregroundColor.opacity(0.7), lineWidth: 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var foregroundColor: Color {
        status.color(scheme: colorScheme)
    }
}

struct ProviderStatusPresentation: Equatable {
    enum Role: Equatable {
        case good
        case warn
        case critical
        case neutral
    }

    let label: String
    let symbolName: String
    let role: Role

    init(state: ProviderState?, isEnabled: Bool) {
        guard isEnabled else {
            self = .off
            return
        }
        switch state {
        case .loaded:
            self = .ready
        case .error:
            self = .error
        case .loading:
            self = .working
        case .none, .unconfigured, .setup:
            self = .needsSetup
        }
    }

    private init(label: String, symbolName: String, role: Role) {
        self.label = label
        self.symbolName = symbolName
        self.role = role
    }

    static let ready = Self(
        label: String(displayLocalized: "Ready", bundle: .module),
        symbolName: "checkmark.circle.fill",
        role: .good
    )

    static let needsSetup = Self(
        label: String(displayLocalized: "Needs setup", bundle: .module),
        symbolName: "wrench.and.screwdriver.fill",
        role: .warn
    )

    static let error = Self(
        label: String(displayLocalized: "Error", bundle: .module),
        symbolName: "exclamationmark.triangle.fill",
        role: .critical
    )

    static let working = Self(
        label: String(displayLocalized: "Working…", bundle: .module),
        symbolName: "clock.arrow.circlepath",
        role: .neutral
    )

    static let off = Self(
        label: String(displayLocalized: "Off", bundle: .module),
        symbolName: "pause.circle.fill",
        role: .neutral
    )

    func color(scheme: ColorScheme) -> Color {
        switch role {
        case .good:
            ProviderVisualStyle.tierColor(.good, scheme: scheme)
        case .warn:
            ProviderVisualStyle.tierColor(.warn, scheme: scheme)
        case .critical:
            ProviderVisualStyle.tierColor(.critical, scheme: scheme)
        case .neutral:
            .secondary
        }
    }
}
