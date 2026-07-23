import Foundation
import Security

struct StoredKeychainItem: Sendable {
    let account: String
    let data: Data
}

protocol KeychainStorage: Sendable {
    func readData(service: String, account: String) throws -> Data?
    func readItems(service: String) throws -> [StoredKeychainItem]
    func replaceData(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String)
}

enum KeychainStorageError: Error {
    case status(OSStatus)
}

struct SecurityKeychainStorage: KeychainStorage {
    func readData(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
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

    func readItems(service: String) throws -> [StoredKeychainItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
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

        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data
            else {
                return nil
            }
            return StoredKeychainItem(account: account, data: data)
        }
    }

    func replaceData(_ data: Data, service: String, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var addQuery = base
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStorageError.status(status)
        }
    }

    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
