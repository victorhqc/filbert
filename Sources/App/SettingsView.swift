import SwiftUI

struct SettingsView: View {
    let viewModel: QuotaViewModel

    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Configure your z.ai API key"))
                .font(.headline)

            SecureField(String(localized: "API Key"), text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveIfValid() }

            HStack {
                Button(String(localized: "Save")) {
                    saveIfValid()
                }
                .disabled(apiKey.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private func saveIfValid() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try viewModel.saveKey(trimmed)
        } catch {
            // Keychain write failed — the error is surfaced by the view model
        }
        apiKey = ""
    }
}
