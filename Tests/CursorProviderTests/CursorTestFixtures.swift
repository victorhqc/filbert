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
            refreshToken: "valid-refresh",
            source: .keychain
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
        onRefresh: (() -> Void)? = nil
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
            return MockURLProtocol.MockResponse(
                data: usageBody,
                statusCode: usageStatus,
                error: usageError
            )
        }
        return session
    }
}
