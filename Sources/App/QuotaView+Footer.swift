import AppKit
import SwiftUI

extension QuotaView {
    var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                HStack {
                    Text(String(localized: "Settings…"))
                        .font(.caption)
                        .layoutPriority(1)
                        .openAndRaiseSettings()

                    Spacer()

                    Button(String(localized: "Quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .font(.caption)
                    .keyboardShortcut("q")
                    .layoutPriority(1)
                }

                Text(AppVersion.currentPresentation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
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
            Button(String(localized: "Update")) {
                updateCoordinator.checkForUpdates()
            }
            .controlSize(.small)
            .accessibilityLabel(
                String.localizedStringWithFormat(String(localized: "Update Filbert to version %@"), version)
            )
        case .restartToUpdate:
            Button(String(localized: "Restart to Update")) {
                updateCoordinator.installNow()
            }
            .controlSize(.small)
            .accessibilityLabel(
                String.localizedStringWithFormat(String(localized: "Restart and update Filbert to version %@"), version)
            )
        }
    }

    private func updateStatusText(_ phase: UpdatePhase) -> String {
        let format = switch phase {
        case .available:
            String(localized: "Filbert %@ is available")
        case .downloading:
            String(localized: "Downloading Filbert %@…")
        case .preparing:
            String(localized: "Preparing Filbert %@…")
        case .readyToInstall:
            String(localized: "Filbert %@ is ready to install")
        case .installing:
            String(localized: "Installing Filbert %@…")
        }
        return String.localizedStringWithFormat(format, phase.version)
    }
}
