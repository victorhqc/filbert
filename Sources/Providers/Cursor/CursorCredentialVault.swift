import Core
import Foundation
import Security

struct CursorTokenPair: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
}

enum CursorCredentialVaultError: Error, LocalizedError {
    case malformedRecord
    case unavailable
    case keychain(KeychainError)

    var errorDescription: String? {
        switch self {
        case .malformedRecord:
            String(localized: "Saved Cursor credentials are incomplete. Re-import them.")
        case .unavailable:
            String(localized: "Sign in to Cursor, then import credentials.")
        case .keychain:
            String(localized: "Unable to access saved Cursor credentials. Check Keychain access and try again.")
        }
    }
}

protocol CursorCredentialVault: Sendable {
    func load() throws -> CursorTokenPair?
    func save(_ pair: CursorTokenPair) throws
    func replaceAccessToken(_ accessToken: String) throws
    func clear() throws
}

struct KeychainCursorCredentialVault: CursorCredentialVault {
    private static let providerId = "cursor"
    private static let accessTokenField = "accessToken"
    private static let refreshTokenField = "refreshToken"

    private let keychain: Keychain

    init(keychain: Keychain = .shared) {
        self.keychain = keychain
    }

    func load() throws -> CursorTokenPair? {
        let fields: [String: String]
        do {
            fields = try keychain.loadFields(for: Self.providerId)
        } catch let error as KeychainError {
            if case let .loadFailed(status) = error, status == errSecItemNotFound {
                return nil
            }
            throw CursorCredentialVaultError.keychain(error)
        }

        guard let accessToken = fields[Self.accessTokenField], !accessToken.isEmpty,
              let refreshToken = fields[Self.refreshTokenField], !refreshToken.isEmpty
        else {
            throw CursorCredentialVaultError.malformedRecord
        }
        return CursorTokenPair(accessToken: accessToken, refreshToken: refreshToken)
    }

    func save(_ pair: CursorTokenPair) throws {
        do {
            try keychain.save(
                [
                    Self.accessTokenField: pair.accessToken,
                    Self.refreshTokenField: pair.refreshToken,
                ],
                for: Self.providerId
            )
        } catch let error as KeychainError {
            throw CursorCredentialVaultError.keychain(error)
        }
    }

    func replaceAccessToken(_ accessToken: String) throws {
        let fields: [String: String]
        do {
            fields = try keychain.loadFields(for: Self.providerId)
        } catch let error as KeychainError {
            throw CursorCredentialVaultError.keychain(error)
        }

        guard let refreshToken = fields[Self.refreshTokenField], !refreshToken.isEmpty else {
            throw CursorCredentialVaultError.malformedRecord
        }
        var updatedFields = fields
        updatedFields[Self.accessTokenField] = accessToken
        do {
            try keychain.save(updatedFields, for: Self.providerId)
        } catch let error as KeychainError {
            throw CursorCredentialVaultError.keychain(error)
        }
    }

    // AC1: drop the Cursor entry from the shared vault (bugs 01).
    func clear() throws {
        do {
            try keychain.delete(for: Self.providerId)
        } catch let error as KeychainError {
            throw CursorCredentialVaultError.keychain(error)
        }
    }
}

struct ExternalCursorTokenPair {
    let accessToken: String
    let refreshToken: String
}

final class CursorImportCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var hasAttemptedBootstrap = false
    private var bootstrapError: (any Error)?

    func loadOrBootstrap(
        loadShared: () throws -> CursorTokenPair?,
        importExternal: () throws -> ExternalCursorTokenPair?,
        saveShared: (CursorTokenPair) throws -> Void
    ) throws -> CursorTokenPair? {
        lock.lock()
        defer { lock.unlock() }

        if let sharedPair = try loadShared() {
            return sharedPair
        }
        guard !hasAttemptedBootstrap else {
            if let bootstrapError {
                throw bootstrapError
            }
            return nil
        }
        hasAttemptedBootstrap = true
        do {
            guard let externalPair = try importExternal() else {
                return nil
            }
            let pair = CursorTokenPair(
                accessToken: externalPair.accessToken,
                refreshToken: externalPair.refreshToken
            )
            try saveShared(pair)
            return pair
        } catch {
            bootstrapError = error
            throw error
        }
    }

    func reimport(
        importExternal: () throws -> ExternalCursorTokenPair?,
        saveShared: (CursorTokenPair) throws -> Void
    ) throws -> CursorTokenPair {
        lock.lock()
        defer { lock.unlock() }

        do {
            guard let externalPair = try importExternal() else {
                throw CursorCredentialVaultError.unavailable
            }
            let pair = CursorTokenPair(
                accessToken: externalPair.accessToken,
                refreshToken: externalPair.refreshToken
            )
            try saveShared(pair)
            hasAttemptedBootstrap = true
            bootstrapError = nil
            return pair
        } catch {
            bootstrapError = error
            throw error
        }
    }
}
