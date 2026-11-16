import Core
import SwiftUI

@MainActor
struct BaseURLOverrideEditor: View {
    let provider: ProviderInfo
    let overrideURL: URL?
    let errorLog: ErrorLog
    let onSave: (URL?) throws -> Void

    @State private var input = ""
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(String(displayLocalized: "Default:", bundle: .module))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(provider.defaultBaseURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                TextField(
                    String(displayLocalized: "Custom base URL (proxy)", bundle: .module),
                    text: $input
                )
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit { save() }
                .onChange(of: input) { _, _ in
                    errorMessage = nil
                }
                Button(String(displayLocalized: "Save", bundle: .module)) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                Button(String(displayLocalized: "Use Default", bundle: .module)) {
                    reset()
                }
                .disabled(overrideURL == nil)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                ErrorLogLink(errorLog: errorLog)
            }
        }
        .onAppear {
            input = overrideURL?.absoluteString ?? ""
            errorMessage = nil
        }
    }

    private var invalidURLMessage: String {
        String(displayLocalized: "Only https URLs are allowed.", bundle: .module)
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: URL?
        if trimmed.isEmpty {
            resolved = nil
        } else if let url = URL(string: trimmed) {
            resolved = url
        } else {
            errorLog.record(
                component: "app",
                operation: "save-override",
                code: "invalid-url",
                providerID: provider.id
            )
            errorMessage = invalidURLMessage
            return
        }

        do {
            try onSave(resolved)
            errorMessage = nil
        } catch {
            errorMessage = invalidURLMessage
        }
    }

    private func reset() {
        do {
            try onSave(nil)
            input = ""
            errorMessage = nil
        } catch {
            errorMessage = invalidURLMessage
        }
    }
}
