import Foundation

struct CursorKeychainCredentials: Sendable, Equatable {
    let accessTokenService: String
    let accessTokenAccount: String
    let refreshTokenService: String
    let refreshTokenAccount: String
}

/// The `client_id` is Cursor's own CLI/desktop client id — hardcoded in the
/// Cursor binary and extracted by reverse-engineering. Cursor offers no
/// developer program to register one, so filbert impersonates Cursor's
/// official client on the refresh path. This is the only place the id
/// appears; a Cursor rotation is a one-line change + release.
enum CursorAuth {
    static let clientId = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    /// Always targets `api2.cursor.sh` directly — the refresh path never goes
    /// through a user proxy override.
    static let tokenEndpoint = URL(string: "https://api2.cursor.sh/oauth/token")!

    static let currentCLIKeychainCredentials = CursorKeychainCredentials(
        accessTokenService: "cursor-access-token",
        accessTokenAccount: "cursor-user",
        refreshTokenService: "cursor-refresh-token",
        refreshTokenAccount: "cursor-user"
    )

    static let legacyCLIKeychainCredentials = CursorKeychainCredentials(
        accessTokenService: "cursor-agent",
        accessTokenAccount: "cursor-access-token",
        refreshTokenService: "cursor-agent",
        refreshTokenAccount: "cursor-refresh-token"
    )

    static let keychainCredentials = [
        currentCLIKeychainCredentials,
        legacyCLIKeychainCredentials,
    ]

    static let sqliteAccessKey = "cursorAuth/accessToken"

    static let sqliteRefreshKey = "cursorAuth/refreshToken"
}
