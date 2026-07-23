@testable import CursorProvider
import Foundation

/// Shared test fixtures and helpers for Cursor provider tests (providers 07).
enum CursorTestFixtures {
    // MARK: - JWT builder

    /// Builds a JWT string with the given `exp` claim (seconds since epoch).
    static func makeJWT(exp: TimeInterval) -> String {
        let header = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}"
        let payload = "{\"exp\":\(Int(exp))}"
        let headerB64 = Data(header.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let payloadB64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "\(headerB64).\(payloadB64).signature"
    }

    // MARK: - Token pair

    static func tokenPair(valid: Bool = false) -> CursorTokenPair {
        let exp: TimeInterval = valid
            ? Date().addingTimeInterval(3600).timeIntervalSince1970
            : 0
        return CursorTokenPair(
            accessToken: valid ? "valid-access" : makeJWT(exp: exp),
            refreshToken: "valid-refresh"
        )
    }

    // MARK: - JSON fixtures

    static func refreshResponse() -> Data {
        Data("""
        {"access_token":"fresh-access-token","token_type":"Bearer","expires_in":3600}
        """.utf8)
    }

    static func shouldLogoutResponse() -> Data {
        Data("""
        {"access_token":"","shouldLogout":true}
        """.utf8)
    }

    static func usageResponse() -> Data {
        jsonToData(usageDict())
    }

    static func usageDict() -> [String: Any] {
        [
            "billingCycleStart": "1700000000000",
            "billingCycleEnd": "1702592000000",
            "isUnlimited": false,
            "planUsage": [
                "totalPercentUsed": 42.5,
                "includedSpend": 5000,
                "limit": 10000,
                "bonusSpend": 2000,
                "autoPercentUsed": 10.0,
                "apiPercentUsed": 30.0,
            ] as [String: Any],
            "spendLimitUsage": [
                "individualUsed": 1500,
                "individualLimit": 2000,
                "pooledUsed": 500,
                "pooledLimit": 1000,
                "pooledRemaining": 500,
            ] as [String: Any],
        ]
    }

    static func legacyResponse() -> Data {
        Data("""
        {
          "billingCycleStart": "1700000000000",
          "billingCycleEnd": "1702592000000",
          "isUnlimited": false,
          "individualUsage": {
            "plan": {
              "used": 5500,
              "limit": 10000,
              "remaining": 4500,
              "totalPercentUsed": 55.0
            },
            "onDemand": {
              "used": 1500,
              "limit": 2000
            }
          }
        }
        """.utf8)
    }

    static func jsonToData(_ json: [String: Any]) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Mock URL session

    static func mockSession(
        refreshStatus: Int = 200,
        refreshBody: Data? = nil,
        usageBody: Data = Data(),
        usageStatus: Int = 200,
        usageError: Error? = nil,
        onRefresh: (() -> Void)? = nil,
        onUsage: (() -> Void)? = nil
    ) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            if request.url?.path.contains("oauth/token") == true {
                onRefresh?()
                return MockURLProtocol.MockResponse(
                    data: refreshBody ?? refreshResponse(),
                    statusCode: refreshStatus,
                    error: nil
                )
            }
            onUsage?()
            return MockURLProtocol.MockResponse(
                data: usageBody,
                statusCode: usageStatus,
                error: usageError
            )
        }
        return session
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.withLock { value }
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock {
            body(&value)
        }
    }
}

struct CursorCredentialVaultCounts {
    let loads: Int
    let saves: Int
    let accessUpdates: Int
}

final class TestCursorCredentialVault: CursorCredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var fields: [String: String]?
    private var shouldFailSave = false
    private var loadCount = 0
    private var saveCount = 0
    private var accessTokenUpdateCount = 0

    init(fields: [String: String]? = nil) {
        self.fields = fields
    }

    func load() throws -> CursorTokenPair? {
        try lock.withLock {
            loadCount += 1
            guard let fields else { return nil }
            guard let accessToken = fields["accessToken"], !accessToken.isEmpty,
                  let refreshToken = fields["refreshToken"], !refreshToken.isEmpty
            else {
                throw CursorCredentialVaultError.malformedRecord
            }
            return CursorTokenPair(accessToken: accessToken, refreshToken: refreshToken)
        }
    }

    func save(_ pair: CursorTokenPair) throws {
        try lock.withLock {
            guard !shouldFailSave else {
                throw CursorCredentialVaultError.keychain(.saveFailed(-1))
            }
            fields = [
                "accessToken": pair.accessToken,
                "refreshToken": pair.refreshToken,
            ]
            saveCount += 1
        }
    }

    func replaceAccessToken(_ accessToken: String) throws {
        try lock.withLock {
            guard var fields,
                  let refreshToken = fields["refreshToken"],
                  !refreshToken.isEmpty
            else {
                throw CursorCredentialVaultError.malformedRecord
            }
            fields["accessToken"] = accessToken
            self.fields = fields
            accessTokenUpdateCount += 1
        }
    }

    func setSaveFailure(_ enabled: Bool) {
        lock.withLock { shouldFailSave = enabled }
    }

    func storedFields() -> [String: String]? {
        lock.withLock { fields }
    }

    func counts() -> CursorCredentialVaultCounts {
        lock.withLock {
            CursorCredentialVaultCounts(
                loads: loadCount,
                saves: saveCount,
                accessUpdates: accessTokenUpdateCount
            )
        }
    }
}
