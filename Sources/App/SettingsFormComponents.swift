import Core
import SwiftUI

struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .background(SettingsWindowConfigurator())
    }
}

struct SettingsInfoButton: View {
    let label: String
    let explanation: String

    @State private var isShowingExplanation = false

    var body: some View {
        Button {
            isShowingExplanation.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .popover(isPresented: $isShowingExplanation, arrowEdge: .bottom) {
            Text(explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
                .padding(14)
        }
    }
}

struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsErrorMessage: View {
    let message: String
    let errorLog: ErrorLog

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            ErrorLogLink(errorLog: errorLog)
        }
    }
}

struct SettingsWorkingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            SettingsCaption(String(displayLocalized: "Working…", bundle: .module))
        }
    }
}

struct ProviderStatusMark: View {
    let status: ProviderStatusPresentation

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: status.symbolName)
            .foregroundStyle(status.color(scheme: colorScheme))
            .help(status.label)
            .accessibilityLabel(status.label)
    }
}

struct ProviderStatusRow: View {
    let status: ProviderStatusPresentation

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LabeledContent(String(displayLocalized: "Status", bundle: .module)) {
            Label(status.label, systemImage: status.symbolName)
                .foregroundStyle(status.color(scheme: colorScheme))
        }
    }
}

/// Menu presets for the schedule. A saved value outside the presets is added,
/// so a value chosen with the older sliders still shows and stays selected.
enum SettingsDurationOptions {
    static let slowIntervalPresets: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60].map { TimeInterval($0 * 60) }
    static let fastIntervalPresets: [TimeInterval] = [10, 15, 30, 45, 60].map(TimeInterval.init)
    static let quietWindowPresets = AutoRefreshPreferences.quietWindowOptions

    static func options(presets: [TimeInterval], including selected: TimeInterval) -> [TimeInterval] {
        guard !presets.contains(selected) else { return presets }
        return (presets + [selected]).sorted()
    }
}

struct DurationMenuPicker: View {
    let title: String
    let presets: [TimeInterval]
    let selection: TimeInterval
    let onSelect: (TimeInterval) -> Void

    var body: some View {
        Picker(
            title,
            selection: Binding(
                get: { selection },
                set: { onSelect($0) }
            )
        ) {
            ForEach(SettingsDurationOptions.options(presets: presets, including: selection), id: \.self) { value in
                Text(refreshDurationText(value))
                    .tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}
