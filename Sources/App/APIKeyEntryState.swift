import Foundation

/// Transient UI state for an API-key entry row. The key remains only in the
/// secure field until a successful Keychain write clears it.
struct APIKeyEntryState {
    private(set) var input = ""
    private(set) var errorMessage: String?

    mutating func updateInput(_ input: String) {
        self.input = input
        errorMessage = nil
    }

    mutating func save(using action: (String) throws -> Void) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try action(trimmed)
            input = ""
            errorMessage = nil
        } catch {
            errorMessage = String(
                localized: "Unable to save the API key. Check Keychain access and try again."
            )
        }
    }

    mutating func clear(using action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = String(
                localized: "Unable to clear the API key. Check Keychain access and try again."
            )
        }
    }
}
