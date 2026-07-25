import Foundation

public extension CursorProvider {
    static var credentialImportActionTitle: String? {
        String(localized: "Re-import Cursor credentials")
    }

    func removeHelper() async throws {
        try tokenStore.clearSharedCredentials()
    }
}
