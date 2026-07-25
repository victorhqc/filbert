import Core
import Foundation
import Security
import SQLite3

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

struct CursorTokenStore: Sendable {
    private let vault: any CursorCredentialVault
    private let externalStorage: any KeychainStorage
    private let externalContext: KeychainAuthenticationContext
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
            externalStorage: SecurityKeychainStorage(),
            externalContext: .shared,
            readSQLiteValue: { CursorTokenStore.defaultReadSQLiteValue(dbPath: $0, key: $1) }
        )
    }

    init(
        vault: any CursorCredentialVault,
        session: URLSession = .shared,
        homeDirectory: String,
        refreshSkew: TimeInterval = 60,
        externalStorage: any KeychainStorage = SecurityKeychainStorage(),
        externalContext: KeychainAuthenticationContext = .shared,
        readSQLiteValue: @escaping @Sendable (String, String) -> String?
    ) {
        self.vault = vault
        self.session = session
        self.homeDirectory = homeDirectory
        self.refreshSkew = refreshSkew
        self.externalStorage = externalStorage
        self.externalContext = externalContext
        self.readSQLiteValue = readSQLiteValue
        importCoordinator = CursorImportCoordinator()
    }

    func loadOrBootstrap() throws -> CursorTokenPair? {
        try importCoordinator.loadOrBootstrap(
            loadShared: { try vault.load() },
            importExternal: { try loadExternalPair() },
            saveShared: { try vault.save($0) }
        )
    }

    /// No normal configuration or refresh path calls this.
    func reimport() throws {
        _ = try importCoordinator.reimport(
            importExternal: { try loadExternalPair() },
            saveShared: { try vault.save($0) }
        )
    }

    /// Leaves Cursor's own first-party stores untouched.
    func clearSharedCredentials() throws {
        try vault.clear()
    }

    private func loadExternalPair() throws -> ExternalCursorTokenPair? {
        for credentials in CursorAuth.keychainCredentials {
            guard let accessToken = try readExternalToken(
                service: credentials.accessTokenService,
                account: credentials.accessTokenAccount
            ) else {
                continue
            }
            guard let refreshToken = try readExternalToken(
                service: credentials.refreshTokenService,
                account: credentials.refreshTokenAccount
            ) else {
                continue
            }
            if let pair = completeExternalPair(accessToken: accessToken, refreshToken: refreshToken) {
                return pair
            }
        }

        return completeExternalPair(
            accessToken: readSQLiteValue(sqlitePath, CursorAuth.sqliteAccessKey),
            refreshToken: readSQLiteValue(sqlitePath, CursorAuth.sqliteRefreshKey)
        )
    }

    /// Reads a UTF-8 token from an external Keychain item via Core's shared
    /// accessor.
    private func readExternalToken(
        service: String,
        account: String
    ) throws -> String? {
        let data: Data?
        do {
            data = try externalStorage.readData(
                service: service,
                account: account,
                authenticationContext: externalContext
            )
        } catch let error as KeychainStorageError {
            throw CursorExternalCredentialError.keychain(error.status)
        }
        guard let data else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw CursorExternalCredentialError.malformedKeychainRecord
        }
        return value
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

    // MARK: - Refresh

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

    /// Minimal subset of a JWT payload: only the `exp` (expiry) claim is read.
    private struct JWTPayload: Decodable {
        let exp: Double
    }

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
              let jwt = try? JSONDecoder().decode(JWTPayload.self, from: data)
        else {
            return nil
        }
        return Date(timeIntervalSince1970: jwt.exp)
    }

    // MARK: - Production external stores

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
