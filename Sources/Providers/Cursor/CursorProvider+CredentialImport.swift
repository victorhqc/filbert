import Foundation

public extension CursorProvider {
    static var credentialImportActionTitle: String? {
        String(localized: "Re-import Cursor credentials")
    }

    // AC1: clearing credentials is Cursor's removal action — it has no helper
    // (bugs 01). The protocol default throws; this clears the shared vault.
    func removeHelper() async throws {
        try tokenStore.clearSharedCredentials()
    }
}
