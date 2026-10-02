import AppKit
import Core
import SwiftUI

@MainActor
struct ErrorLogLink: View {
    let errorLog: ErrorLog

    var body: some View {
        if let fileURL = errorLog.availableFileURL {
            Button(String(localized: "Show Logs", bundle: .module)) {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
            .buttonStyle(.link)
            .font(.caption)
            .help(fileURL.path)
            .accessibilityHint(String(localized: "Reveal the error log in Finder.", bundle: .module))
        } else {
            Text(String(localized: "The error log is unavailable.", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
