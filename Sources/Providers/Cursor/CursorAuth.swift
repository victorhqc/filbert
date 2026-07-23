import Foundation

/// The Keychain locations that hold a Cursor CLI OAuth token pair.
struct CursorKeychainCredentials: Sendable, Equatable {
    let accessTokenService: String
    let accessTokenAccount: String
    let refreshTokenService: String
    let refreshTokenAccount: String
}

/// Cursor first-party OAuth constants (providers 07 AC5/AC11).
///
/// The `client_id` is Cursor's own CLI/desktop client id — hardcoded in the
/// Cursor binary and extracted by reverse-engineering. Cursor offers no
/// developer program to register one, so filbert impersonates Cursor's
/// official client on the refresh path. This is the **only** place the id
/// appears; a Cursor rotation is a one-line change + release (providers 07
/// AC11).
enum CursorAuth {
    /// Cursor's first-party CLI/desktop client id.
    static let clientId = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    /// OAuth token endpoint. Always targets `api2.cursor.sh` directly — the
    /// refresh path never goes through a user proxy override (providers 07 AC5).
    static let tokenEndpoint = URL(string: "https://api2.cursor.sh/oauth/token")!

    /// Credentials written by the current Cursor Agent CLI (`agent login`).
    static let currentCLIKeychainCredentials = CursorKeychainCredentials(
        accessTokenService: "cursor-access-token",
        accessTokenAccount: "cursor-user",
        refreshTokenService: "cursor-refresh-token",
        refreshTokenAccount: "cursor-user"
    )

    /// Credentials for the `cursor-agent` Keychain layout.
    static let legacyCLIKeychainCredentials = CursorKeychainCredentials(
        accessTokenService: "cursor-agent",
        accessTokenAccount: "cursor-access-token",
        refreshTokenService: "cursor-agent",
        refreshTokenAccount: "cursor-refresh-token"
    )

    /// Lookup covers all supported Cursor Agent Keychain layouts.
    static let keychainCredentials = [
        currentCLIKeychainCredentials,
        legacyCLIKeychainCredentials,
    ]

    /// SQLite key storing the access token in Cursor Desktop's `state.vscdb`.
    static let sqliteAccessKey = "cursorAuth/accessToken"

    /// SQLite key storing the refresh token in Cursor Desktop's `state.vscdb`.
    static let sqliteRefreshKey = "cursorAuth/refreshToken"
}
