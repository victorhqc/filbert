import AppKit
import Core
import SwiftUI

struct SettingsWindowConfigurator: NSViewRepresentable {
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
            window?.contentMinSize = NSSize(width: 520, height: 420)
        }
    }
}

struct SettingsScrollColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(SettingsWindowConfigurator())
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
                        Toggle(
                            String(localized: "Enabled"),
                            isOn: Binding(
                                get: { isEnabled },
                                set: { enabled in
                                    onEnabledChange(enabled)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String.localizedStringWithFormat(
                                String(localized: "Enable %@"),
                                provider.displayName
                            )
                        )
                        .accessibilityValue(
                            isEnabled
                                ? String(localized: "Enabled")
                                : String(localized: "Disabled")
                        )
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
        switch status.role {
        case .good:
            ProviderVisualStyle.tierColor(.good, scheme: colorScheme)
        case .critical:
            ProviderVisualStyle.tierColor(.critical, scheme: colorScheme)
        case .neutral:
            .secondary
        }
    }
}

struct ProviderStatusPresentation {
    enum Role {
        case good
        case critical
        case neutral
    }

    let label: String
    let symbolName: String
    let role: Role

    static func apiKey(_ state: ProviderState) -> Self {
        switch state {
        case .loaded:
            Self(
                label: String(localized: "Configured"),
                symbolName: "checkmark.circle.fill",
                role: .good
            )
        case .error:
            error
        case .loading:
            working
        case .unconfigured, .setup:
            unconfigured
        }
    }

    static func apiKeyFree(_ state: ProviderState) -> Self {
        switch state {
        case .loaded:
            Self(
                label: String(localized: "Ready"),
                symbolName: "checkmark.circle.fill",
                role: .good
            )
        case .error:
            error
        case .loading:
            working
        case .setup:
            Self(
                label: String(localized: "Setup needed"),
                symbolName: "wrench.and.screwdriver.fill",
                role: .neutral
            )
        case .unconfigured:
            unconfigured
        }
    }

    static let disabled = Self(
        label: String(localized: "Disabled"),
        symbolName: "pause.circle.fill",
        role: .neutral
    )

    private static let error = Self(
        label: String(localized: "Error"),
        symbolName: "exclamationmark.triangle.fill",
        role: .critical
    )

    private static let working = Self(
        label: String(localized: "Working…"),
        symbolName: "clock.arrow.circlepath",
        role: .neutral
    )

    private static let unconfigured = Self(
        label: String(localized: "Unconfigured"),
        symbolName: "circle.dashed",
        role: .neutral
    )
}
