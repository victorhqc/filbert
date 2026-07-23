import Foundation
import Security
import SQLite3

/// A loaded Cursor access/refresh token pair and where it came from
/// (providers 07 AC4).
struct CursorTokenPair: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let source: Source
    let keychainCredentials: CursorKeychainCredentials?

    /// Where the token was read from. Only the Keychain source is persisted
    /// back to on refresh — writing to Cursor's `state.vscdb` while the
    /// desktop app may have it open risks a conflict, so SQLite-sourced
    /// tokens are refreshed in-memory only (providers 07 Risks).
    enum Source: Sendable, Equatable {
        case keychain
        case sqlite
    }

    init(
        accessToken: String,
        refreshToken: String,
        source: Source,
        keychainCredentials: CursorKeychainCredentials? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.source = source
        self.keychainCredentials = keychainCredentials
    }
}

/// Reads Cursor auth tokens from the two supported local stores, Keychain
/// first, and refreshes the short-lived JWT when needed (providers 07 AC4/AC5).
///
/// Token sources, in priority order:
/// 1. **Keychain** — Cursor Agent stores its access and refresh tokens in one
///    of its supported Keychain layouts after `agent login`.
/// 2. **SQLite** — Cursor Desktop's `state.vscdb`, keys
///    `cursorAuth/accessToken` / `cursorAuth/refreshToken`.
///
/// All filesystem/keychain access is injected as closures so lookup order and
/// missing stores are unit-testable without touching real credentials.
struct CursorTokenStore: Sendable {
    private let readKeychain: @Sendable (String, String) -> String?
    private let writeKeychain: @Sendable (String, String, String) -> Void
    private let readSQLiteValue: @Sendable (String, String) -> String?
    private let homeDirectory: String
    private let session: URLSession
    /// Refresh when `exp` is within this many seconds of now (providers 07 AC5).
    private let refreshSkew: TimeInterval

    /// Production initializer: uses real Keychain and SQLite reads.
    init(
        session: URLSession = .shared,
        homeDirectory: String = NSHomeDirectory(),
        refreshSkew: TimeInterval = 60
    ) {
        self.init(
            session: session,
            homeDirectory: homeDirectory,
            refreshSkew: refreshSkew,
            readKeychain: { CursorTokenStore.defaultReadKeychain(service: $0, account: $1) },
            writeKeychain: { CursorTokenStore.defaultWriteKeychain(service: $0, account: $1, value: $2) },
            readSQLiteValue: { CursorTokenStore.defaultReadSQLiteValue(dbPath: $0, key: $1) }
        )
    }

    /// Testable initializer with injected keychain/SQLite access.
    init(
        session: URLSession,
        homeDirectory: String,
        refreshSkew: TimeInterval = 60,
        readKeychain: @escaping @Sendable (String, String) -> String?,
        writeKeychain: @escaping @Sendable (String, String, String) -> Void,
        readSQLiteValue: @escaping @Sendable (String, String) -> String?
    ) {
        self.session = session
        self.homeDirectory = homeDirectory
        self.refreshSkew = refreshSkew
        self.readKeychain = readKeychain
        self.writeKeychain = writeKeychain
        self.readSQLiteValue = readSQLiteValue
    }

    /// Convenience initializer for tests that only need injected reads
    /// without a session (e.g. testing `load()` ordering).
    init(
        homeDirectory: String,
        readKeychain: @escaping @Sendable (String, String) -> String?,
        writeKeychain: @escaping @Sendable (String, String, String) -> Void,
        readSQLiteValue: @escaping @Sendable (String, String) -> String?
    ) {
        self.init(
            session: .shared,
            homeDirectory: homeDirectory,
            refreshSkew: 60,
            readKeychain: readKeychain,
            writeKeychain: writeKeychain,
            readSQLiteValue: readSQLiteValue
        )
    }

    // MARK: - Loading (providers 07 AC4)

    /// Returns the first complete, non-empty token pair, or `nil` when neither
    /// source has one. Never throws.
    func load() -> CursorTokenPair? {
        // Keychain first, accepting both supported Cursor Agent layouts.
        for credentials in CursorAuth.keychainCredentials {
            if let pair = completePair(
                accessToken: readKeychain(
                    credentials.accessTokenService,
                    credentials.accessTokenAccount
                ),
                refreshToken: readKeychain(
                    credentials.refreshTokenService,
                    credentials.refreshTokenAccount
                ),
                source: .keychain,
                keychainCredentials: credentials
            ) {
                return pair
            }
        }

        // SQLite fallback.
        if let pair = completePair(
            accessToken: readSQLiteValue(sqlitePath, CursorAuth.sqliteAccessKey),
            refreshToken: readSQLiteValue(sqlitePath, CursorAuth.sqliteRefreshKey),
            source: .sqlite
        ) {
            return pair
        }

        return nil
    }

    private func completePair(
        accessToken: String?,
        refreshToken: String?,
        source: CursorTokenPair.Source,
        keychainCredentials: CursorKeychainCredentials? = nil
    ) -> CursorTokenPair? {
        guard let accessToken,
              !accessToken.isEmpty,
              let refreshToken,
              !refreshToken.isEmpty
        else {
            return nil
        }
        return CursorTokenPair(
            accessToken: accessToken,
            refreshToken: refreshToken,
            source: source,
            keychainCredentials: keychainCredentials
        )
    }

    private var sqlitePath: String {
        "\(homeDirectory)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    // MARK: - Refresh (providers 07 AC5/AC11)

    /// Returns a valid access token, refreshing the JWT when the current one
    /// is expired or within the skew window. Persists the refreshed token back
    /// to the Keychain source; SQLite-sourced tokens are refreshed in-memory
    /// only (providers 07 Risks).
    func ensureValidAccessToken(_ pair: CursorTokenPair) async throws -> String {
        // When the JWT exp can be decoded, refresh only if it's within the
        // skew window. When exp cannot be decoded (not a JWT or malformed),
        // use the token as-is — the usage call will fail with 401 if it's
        // actually expired, which surfaces as a typed error (providers 07 AC5).
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

        // A 4xx on /oauth/token means Cursor rotated its client_id —
        // filbert's embedded constant is now stale and needs an update
        // (providers 07 AC11).
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

        // `shouldLogout` or an empty access token means the session is
        // genuinely expired — the user must re-run `agent login`
        // (providers 07 AC5).
        guard refreshResponse.shouldLogout != true,
              let accessToken = refreshResponse.accessToken,
              !accessToken.isEmpty
        else {
            throw CursorError.sessionExpired
        }

        // Persist back to the Keychain source only (providers 07 Risks).
        if pair.source == .keychain {
            let credentials = pair.keychainCredentials ?? CursorAuth.legacyCLIKeychainCredentials
            writeKeychain(
                credentials.accessTokenService,
                credentials.accessTokenAccount,
                accessToken
            )
        }

        return accessToken
    }

    // MARK: - JWT expiry (no third-party library)

    /// Decodes the `exp` claim from a JWT payload without signature
    /// verification. Returns `nil` when the token is not a decodable JWT.
    static func jwtExpiry(_ token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
        // base64url → base64
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore padding stripped in base64url.
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

    // MARK: - Production keychain access

    /// Reads a generic-password item from the macOS Keychain. Returns `nil`
    /// when the item does not exist (providers 07 AC4).
    private static func defaultReadKeychain(
        service: String,
        account: String
    ) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    /// Writes a generic-password item to the macOS Keychain, replacing any
    /// existing entry for the same service/account.
    private static func defaultWriteKeychain(
        service: String,
        account: String,
        value: String
    ) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        guard updateStatus == errSecItemNotFound else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Production SQLite access

    /// Opens `state.vscdb` read-only and reads a single `ItemTable` value.
    /// Returns `nil` when the database or key is unavailable — never throws
    /// (providers 07 AC4).
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

// MARK: - Wire types

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

/// `SQLITE_TRANSIENT` asks SQLite to copy Swift's temporary UTF-8 buffer
/// before `sqlite3_bind_text` returns.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
