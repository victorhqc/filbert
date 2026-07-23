import Foundation
import LocalAuthentication
import Security

final class KeychainAuthenticationContext: @unchecked Sendable {
    let localAuthenticationContext = LAContext()
}

struct StoredKeychainItem: Sendable {
    let account: String
    let data: Data
}

protocol KeychainStorage: Sendable {
    func readData(
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws -> Data?
    func readLegacyItems(
        service: String,
        accountPrefix: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws -> [StoredKeychainItem]
    func replaceData(
        _ data: Data,
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws
    func delete(
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    )
}

enum KeychainStorageError: Error {
    case status(OSStatus)
}

struct SecurityKeychainStorage: KeychainStorage {
    func readData(
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext.localAuthenticationContext,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainStorageError.status(errSecDecode)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStorageError.status(status)
        }
    }

    func readLegacyItems(
        service: String,
        accountPrefix: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws -> [StoredKeychainItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: authenticationContext.localAuthenticationContext,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw KeychainStorageError.status(status)
        }
        guard let items = result as? [[String: Any]] else {
            throw KeychainStorageError.status(errSecDecode)
        }

        var legacyItems: [StoredKeychainItem] = []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(accountPrefix),
                  let data = try readData(
                      service: service,
                      account: account,
                      authenticationContext: authenticationContext
                  )
            else {
                continue
            }
            legacyItems.append(StoredKeychainItem(account: account, data: data))
        }
        return legacyItems
    }

    func replaceData(
        _ data: Data,
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: authenticationContext.localAuthenticationContext,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            attributes as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = base
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStorageError.status(addStatus)
            }
        default:
            throw KeychainStorageError.status(updateStatus)
        }
    }

    func delete(
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: authenticationContext.localAuthenticationContext,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
