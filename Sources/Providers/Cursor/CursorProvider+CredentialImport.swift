import Core
import Foundation

public extension CursorProvider {
    static var credentialImportActionTitle: String? {
        String(localized: "Re-import Cursor credentials")
    }

    func canRemoveHelper() -> Bool {
        isConfigured()
    }

    func importCredentials() async throws {
        do {
            try tokenStore.reimport()
        } catch CursorCredentialVaultError.unavailable {
            throw ProviderSetupError.missingCredentials
        } catch {
            guard !isCredentialCancellation(error) else { throw CancellationError() }
            throw error
        }
    }

    func removeHelper() async throws {
        do {
            try tokenStore.clearSharedCredentials()
        } catch where isCredentialCancellation(error) {
            throw CancellationError()
        }
    }
}
