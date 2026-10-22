import AppKit
import Core
import SwiftUI

extension QuotaView {
    var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(displayLocalized: "Settings…", bundle: .module))
                    .font(.caption)
                    .layoutPriority(1)
                    .openAndRaiseSettings()

                Spacer(minLength: 0)

                Text(AppVersion.currentPresentation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(AppVersion.currentPresentation)

                Spacer(minLength: 0)

                Button(String(displayLocalized: "Quit", bundle: .module)) {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .keyboardShortcut("q")
                .layoutPriority(1)
            }

            if let update = updateCoordinator.popoverUpdate {
                updateAvailabilityRow(update)
            }
        }
    }

    private func updateAvailabilityRow(_ update: PopoverUpdate) -> some View {
        HStack(spacing: 8) {
            if update.showsProgress {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(updateStatusText(update.phase))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 0)

            if let action = update.action {
                updateActionButton(action, version: update.phase.version)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func updateActionButton(_ action: PopoverUpdate.Action, version: String) -> some View {
        switch action {
        case .update:
            Button(String(displayLocalized: "Update", bundle: .module)) {
                updateCoordinator.checkForUpdates()
            }
            .controlSize(.small)
            .accessibilityLabel(
                String.localizedStringWithFormat(
                    String(displayLocalized: "Update Filbert to version %@", bundle: .module),
                    version
                )
            )
        }
    }

    private func updateStatusText(_ phase: UpdatePhase) -> String {
        let format = switch phase {
        case .available:
            String(displayLocalized: "Filbert %@ is available", bundle: .module)
        case .downloading:
            String(displayLocalized: "Downloading Filbert %@…", bundle: .module)
        case .preparing:
            String(displayLocalized: "Preparing Filbert %@…", bundle: .module)
        }
        return String.localizedStringWithFormat(format, phase.version)
    }
}
