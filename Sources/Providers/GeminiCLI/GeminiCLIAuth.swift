import Foundation
import Security

enum GeminiCLILog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[GeminiCLIProvider] \(message())\n".utf8))
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

enum GeminiHTTPError: Error, Equatable, Sendable {
    case network
    case http(Int)
}

struct GeminiHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let retryAfter: TimeInterval?
}

protocol GeminiHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GeminiHTTPResponse
}

final class GeminiRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct URLSessionGeminiHTTPTransport: GeminiHTTPTransport {
    private static let allowedHosts = [
        "cloudcode-pa.googleapis.com",
        "oauth2.googleapis.com",
    ]

    let session: URLSession

    func send(_ request: URLRequest) async throws -> GeminiHTTPResponse {
        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiHTTPError.network
            }
            guard let requestURL = request.url,
                  let responseURL = httpResponse.url,
                  requestURL.scheme == "https",
                  Self.allowedHosts.contains(requestURL.host ?? ""),
                  responseURL.scheme == "https",
                  responseURL.host == requestURL.host
            else {
                throw GeminiHTTPError.network
            }
            GeminiCLILog.log(
                "status=\(httpResponse.statusCode) latencyMs=\(elapsedMilliseconds(since: started))"
            )
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
                .flatMap { $0 >= 0 ? min($0, 30) : nil }
            return GeminiHTTPResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                retryAfter: retryAfter
            )
        } catch let error as GeminiHTTPError {
            GeminiCLILog.log(
                "network failure latencyMs=\(elapsedMilliseconds(since: started))"
            )
            throw error
        } catch {
            GeminiCLILog.log(
                "network failure latencyMs=\(elapsedMilliseconds(since: started))"
            )
            throw GeminiHTTPError.network
        }
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

struct GeminiHTTPClient: Sendable {
    private let transport: any GeminiHTTPTransport
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        transport: any GeminiHTTPTransport,
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        self.transport = transport
        self.sleep = sleep ?? { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    func send(_ request: URLRequest) async throws -> Data {
        for attempt in 0 ..< 3 {
            do {
                let response = try await transport.send(request)
                if response.statusCode == 429 || (500 ... 599).contains(response.statusCode) {
                    guard attempt < 2 else {
                        throw GeminiHTTPError.http(response.statusCode)
                    }
                    let delay = min(response.retryAfter ?? pow(2, Double(attempt)) * 0.5, 30)
                    try await sleep(delay)
                    continue
                }
                guard response.statusCode == 200 else {
                    throw GeminiHTTPError.http(response.statusCode)
                }
                return response.data
            } catch let error as GeminiHTTPError {
                throw error
            } catch {
                throw GeminiHTTPError.network
            }
        }
        throw GeminiHTTPError.network
    }
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
    private let configuredProject: String?

    init(
        http: GeminiHTTPClient,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.http = http
        configuredProject = environment["GOOGLE_CLOUD_PROJECT"]
            ?? environment["GOOGLE_CLOUD_PROJECT_ID"]
    }

    func resolveProject(accessToken: String) async throws -> String {
        let metadata = GeminiClientMetadata(
            ideType: "IDE_UNSPECIFIED",
            platform: "PLATFORM_UNSPECIFIED",
            pluginType: "GEMINI",
            duetProject: configuredProject
        )
        let requestBody = GeminiLoadCodeAssistRequest(
            cloudaicompanionProject: configuredProject,
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
        if let project = response.cloudaicompanionProject, !project.isEmpty {
            return project
        }
        if let configuredProject, !configuredProject.isEmpty {
            return configuredProject
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
        } catch {
            throw GeminiCLIError.network
        }
    }
}
