import Foundation
import OSLog
import Security

protocol GeminiLogSink: Sendable {
    func requestCompleted(statusCode: Int, latencyMilliseconds: Int)
    func requestFailed(latencyMilliseconds: Int)
}

struct GeminiOSLogSink: GeminiLogSink {
    private let logger: Logger

    init() {
        logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.victorhqc.filbert",
            category: "GeminiCLIProvider"
        )
    }

    func requestCompleted(statusCode: Int, latencyMilliseconds: Int) {
        logger.debug("Gemini request completed status=\(statusCode) latencyMs=\(latencyMilliseconds)")
    }

    func requestFailed(latencyMilliseconds: Int) {
        logger.debug("Gemini request failed latencyMs=\(latencyMilliseconds)")
    }
}

enum GeminiCredentialError: Error, Equatable, Sendable {
    case itemNotFound
    case accessDenied(OSStatus)
    case invalidPayload
}

struct GeminiCredentials: Equatable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?
}

extension GeminiCredentials: CustomStringConvertible {
    var description: String {
        let accessTokenDescription = accessToken == nil ? "nil" : "<redacted>"
        let refreshTokenDescription = refreshToken == nil ? "nil" : "<redacted>"
        return """
        GeminiCredentials(accessToken: \(accessTokenDescription), refreshToken: \
        \(refreshTokenDescription), expiresAt: \(String(describing: expiresAt)))
        """
    }
}

protocol GeminiCredentialStore: Sendable {
    func load() throws -> GeminiCredentials?
}

struct GeminiKeychainStore: GeminiCredentialStore {
    private let service = "gemini-cli-oauth"
    private let account = "main-account"

    func load() throws -> GeminiCredentials? {
        // SecItemCopyMatching requires an untyped query dictionary.
        // swiftlint:disable:next no_any_type
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw GeminiCredentialError.accessDenied(status)
        }
        guard let data = result as? Data else {
            throw GeminiCredentialError.invalidPayload
        }

        return try Self.decodeCredentials(from: data)
    }

    static func decodeCredentials(from data: Data) throws -> GeminiCredentials {
        do {
            let stored = try JSONDecoder().decode(
                GeminiStoredCredentialEnvelope.self,
                from: data
            )
            guard stored.token.accessToken?.isEmpty == false
                || stored.token.refreshToken?.isEmpty == false
            else {
                throw GeminiCredentialError.invalidPayload
            }
            return GeminiCredentials(
                accessToken: stored.token.accessToken,
                refreshToken: stored.token.refreshToken,
                expiresAt: stored.token.expiresAt.map {
                    Date(timeIntervalSince1970: TimeInterval($0) / 1000)
                }
            )
        } catch let error as GeminiCredentialError {
            throw error
        } catch {
            throw GeminiCredentialError.invalidPayload
        }
    }
}

private struct GeminiStoredCredentialEnvelope: Decodable {
    let token: GeminiStoredToken
}

private struct GeminiStoredToken: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Int64?
}

struct GeminiOAuthClient: Sendable {
    private let http: GeminiHTTPClient

    init(http: GeminiHTTPClient) {
        self.http = http
    }

    func exchange(refreshToken: String) async throws -> String {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GeminiCLIError.internalInconsistency
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id=681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com",
            "grant_type=refresh_token",
            "refresh_token=\(Self.formEncoded(refreshToken))",
        ].joined(separator: "&").data(using: .utf8)

        do {
            let data = try await http.send(request)
            let response = try JSONDecoder().decode(
                GeminiOAuthTokenResponse.self,
                from: data
            )
            guard !response.accessToken.isEmpty else {
                throw GeminiCLIError.signedOut
            }
            return response.accessToken
        } catch let error as GeminiCLIError {
            throw error
        } catch let error as GeminiHTTPError {
            switch error {
            case .network:
                throw GeminiCLIError.network
            case let .http(status) where [400, 401, 403].contains(status):
                throw GeminiCLIError.signedOut
            case .http(429):
                throw GeminiCLIError.rateLimited
            case let .http(status):
                throw GeminiCLIError.http(status)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GeminiCLIError.decoding
        }
    }

    private static func formEncoded(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(
                charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
            )
        ) ?? value
    }
}

private struct GeminiOAuthTokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct GeminiCodeAssistClient: Sendable {
    private let http: GeminiHTTPClient

    init(http: GeminiHTTPClient) {
        self.http = http
    }

    func resolveProject(accessToken: String) async throws -> String {
        let metadata = GeminiClientMetadata(
            ideType: "IDE_UNSPECIFIED",
            platform: "PLATFORM_UNSPECIFIED",
            pluginType: "GEMINI",
            duetProject: nil
        )
        let requestBody = GeminiLoadCodeAssistRequest(
            cloudaicompanionProject: nil,
            metadata: metadata
        )
        let data = try await post(
            path: "loadCodeAssist",
            accessToken: accessToken,
            body: requestBody
        )
        let response: GeminiLoadCodeAssistResponse
        do {
            response = try JSONDecoder().decode(
                GeminiLoadCodeAssistResponse.self,
                from: data
            )
        } catch {
            throw GeminiCLIError.decoding
        }
        if let project = response.projectIdentifier {
            return project
        }
        throw GeminiCLIError.projectSetupRequired
    }

    func retrieveQuota(
        accessToken: String,
        project: String
    ) async throws -> GeminiQuotaResponse {
        let data = try await post(
            path: "retrieveUserQuota",
            accessToken: accessToken,
            body: GeminiQuotaRequest(project: project)
        )
        do {
            return try JSONDecoder().decode(GeminiQuotaResponse.self, from: data)
        } catch {
            throw GeminiCLIError.decoding
        }
    }

    private func post(
        path: String,
        accessToken: String,
        body: some Encodable
    ) async throws -> Data {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:\(path)") else {
            throw GeminiCLIError.internalInconsistency
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        do {
            return try await http.send(request)
        } catch let error as GeminiHTTPError {
            switch error {
            case .network:
                throw GeminiCLIError.network
            case .http(401):
                throw GeminiCLIError.signedOut
            case .http(403):
                throw GeminiCLIError.projectSetupRequired
            case .http(429):
                throw GeminiCLIError.rateLimited
            case let .http(status):
                throw GeminiCLIError.http(status)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GeminiCLIError.network
        }
    }
}
