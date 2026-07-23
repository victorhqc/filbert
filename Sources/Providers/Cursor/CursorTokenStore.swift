import Foundation
import LocalAuthentication
import Security
import SQLite3

final class CursorKeychainAuthenticationContext: @unchecked Sendable {
    let localAuthenticationContext = LAContext()
}

enum CursorExternalCredentialError: Error, Equatable, LocalizedError {
    case keychain(OSStatus)
    case malformedKeychainRecord

    var errorDescription: String? {
        switch self {
        case .keychain:
            String(localized: "Unable to access Cursor credentials. Check Keychain access and try again.")
        case .malformedKeychainRecord:
            String(localized: "Cursor credentials are invalid. Sign in to Cursor, then re-import them.")
        }
    }
}

/// Loads Cursor credentials from Filbert's shared vault. When the vault has
/// no Cursor record, one bootstrap attempt imports the first complete pair
/// from Cursor Agent Keychain layouts, then Cursor Desktop SQLite.
struct CursorTokenStore: Sendable {
    private let vault: any CursorCredentialVault
    private let readKeychain: @Sendable (
        String,
        String,
        CursorKeychainAuthenticationContext
    ) throws -> String?
    private let readSQLiteValue: @Sendable (String, String) -> String?
    private let homeDirectory: String
    private let session: URLSession
    private let refreshSkew: TimeInterval
    private let importCoordinator: CursorImportCoordinator

    init(
        session: URLSession = .shared,
        homeDirectory: String = NSHomeDirectory(),
        refreshSkew: TimeInterval = 60
    ) {
        self.init(
            vault: KeychainCursorCredentialVault(),
            session: session,
            homeDirectory: homeDirectory,
            refreshSkew: refreshSkew,
            readKeychainWithContext: {
                try CursorTokenStore.defaultReadKeychain(
                    service: $0,
                    account: $1,
                    authenticationContext: $2
                )
            },
            readSQLiteValue: { CursorTokenStore.defaultReadSQLiteValue(dbPath: $0, key: $1) }
        )
    }

    init(
        vault: any CursorCredentialVault,
        session: URLSession = .shared,
        homeDirectory: String,
        refreshSkew: TimeInterval = 60,
        readKeychain: @escaping @Sendable (String, String) -> String?,
        readSQLiteValue: @escaping @Sendable (String, String) -> String?
    ) {
        self.init(
            vault: vault,
            session: session,
            homeDirectory: homeDirectory,
            refreshSkew: refreshSkew,
            readKeychainWithContext: { service, account, _ in
                readKeychain(service, account)
            },
            readSQLiteValue: readSQLiteValue
        )
    }

    init(
        vault: any CursorCredentialVault,
        session: URLSession = .shared,
        homeDirectory: String,
        refreshSkew: TimeInterval = 60,
        readKeychainWithContext: @escaping @Sendable (
            String,
            String,
            CursorKeychainAuthenticationContext
        ) throws -> String?,
        readSQLiteValue: @escaping @Sendable (String, String) -> String?
    ) {
        self.vault = vault
        self.session = session
        self.homeDirectory = homeDirectory
        self.refreshSkew = refreshSkew
        readKeychain = readKeychainWithContext
        self.readSQLiteValue = readSQLiteValue
        importCoordinator = CursorImportCoordinator()
    }

    /// Loads the shared Cursor pair and performs at most one initial import.
    func loadOrBootstrap() throws -> CursorTokenPair? {
        try importCoordinator.loadOrBootstrap(
            loadShared: { try vault.load() },
            importExternal: { try loadExternalPair() },
            saveShared: { try vault.save($0) }
        )
    }

    /// Deliberately re-reads Cursor-owned stores and persists the result into
    /// Filbert's vault. No normal configuration or refresh path calls this.
    func reimport() throws {
        _ = try importCoordinator.reimport(
            importExternal: { try loadExternalPair() },
            saveShared: { try vault.save($0) }
        )
    }

    private func loadExternalPair() throws -> ExternalCursorTokenPair? {
        let authenticationContext = CursorKeychainAuthenticationContext()
        for credentials in CursorAuth.keychainCredentials {
            guard let accessToken = try readKeychain(
                credentials.accessTokenService,
                credentials.accessTokenAccount,
                authenticationContext
            ) else {
                continue
            }
            let refreshToken = try readKeychain(
                credentials.refreshTokenService,
                credentials.refreshTokenAccount,
                authenticationContext
            )
            if let pair = completeExternalPair(accessToken: accessToken, refreshToken: refreshToken) {
                return pair
            }
        }

        return completeExternalPair(
            accessToken: readSQLiteValue(sqlitePath, CursorAuth.sqliteAccessKey),
            refreshToken: readSQLiteValue(sqlitePath, CursorAuth.sqliteRefreshKey)
        )
    }

    private func completeExternalPair(
        accessToken: String?,
        refreshToken: String?
    ) -> ExternalCursorTokenPair? {
        guard let accessToken, !accessToken.isEmpty,
              let refreshToken, !refreshToken.isEmpty
        else {
            return nil
        }
        return ExternalCursorTokenPair(accessToken: accessToken, refreshToken: refreshToken)
    }

    private var sqlitePath: String {
        "\(homeDirectory)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    // MARK: - Refresh (providers 07 AC5/AC11)

    /// Returns a valid access token, refreshing the JWT when the current one
    /// is expired or within the skew window.
    func ensureValidAccessToken(_ pair: CursorTokenPair) async throws -> String {
        if let expiry = Self.jwtExpiry(pair.accessToken) {
            guard expiry > Date().addingTimeInterval(refreshSkew) else {
                return try await refresh(pair)
            }
        }
        return pair.accessToken
    }

    private func refresh(_ pair: CursorTokenPair) async throws -> String {
        var request = URLRequest(url: CursorAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RefreshRequest(
            grantType: "refresh_token",
            refreshToken: pair.refreshToken,
            clientId: CursorAuth.clientId
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CursorError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorError.network(URLError(.badServerResponse))
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                throw CursorError.http(429)
            }
            if (400 ... 499).contains(httpResponse.statusCode) {
                throw CursorError.clientIdRejected
            }
            throw CursorError.http(httpResponse.statusCode)
        }

        let refreshResponse: RefreshResponse
        do {
            refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
        } catch {
            throw CursorError.decoding(error)
        }

        guard refreshResponse.shouldLogout != true,
              let accessToken = refreshResponse.accessToken,
              !accessToken.isEmpty
        else {
            throw CursorError.sessionExpired
        }

        try vault.replaceAccessToken(accessToken)
        return accessToken
    }

    // MARK: - JWT expiry (no third-party library)

    static func jwtExpiry(_ token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? NSNumber
        else {
            return nil
        }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    // MARK: - Production external stores

    private static func defaultReadKeychain(
        service: String,
        account: String,
        authenticationContext: CursorKeychainAuthenticationContext
    ) throws -> String? {
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
        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw CursorExternalCredentialError.keychain(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw CursorExternalCredentialError.malformedKeychainRecord
        }
        return value
    }

    private static func defaultReadSQLiteValue(dbPath: String, key: String) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            dbPath,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return String(cString: cString)
    }
}

private struct RefreshRequest: Encodable {
    let grantType: String
    let refreshToken: String
    let clientId: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
        case clientId = "client_id"
    }
}

private struct RefreshResponse: Decodable {
    let accessToken: String?
    let shouldLogout: Bool?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case shouldLogout
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
