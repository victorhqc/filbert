import Foundation

enum CodexAppServerError: Error, Equatable, Sendable {
    case launchFailed
    case unsupportedVersion
    case signedOut
    case childExited
    case malformedResponse
    case timedOut
}

extension CodexAppServerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .launchFailed, .childExited:
            String(localized: "Codex stopped before usage limits could be read. Try again.")
        case .unsupportedVersion:
            String(localized: "Update Codex to a version that supports usage limits.")
        case .signedOut:
            String(localized: "Sign in to Codex by running codex login.")
        case .malformedResponse:
            String(localized: "Codex returned an unsupported usage-limits response. Update Codex and try again.")
        case .timedOut:
            String(localized: "Codex did not respond in time. Try again.")
        }
    }
}

struct CodexRateLimitReadResult: Decodable, Sendable {
    let rateLimits: CodexRateLimitSnapshot?
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
}

struct CodexRateLimitSnapshot: Decodable, Sendable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let credits: CodexCredits?
}

struct CodexRateLimitWindow: Decodable, Sendable {
    let usedPercent: Double?
    let resetsAt: TimeInterval?
    let windowDurationMins: Int?
}

struct CodexCredits: Decodable, Sendable {
    let balance: String?
    let unlimited: Bool?
}

/// Executes one bounded, read-only Codex app-server request (providers 05 AC3).
struct CodexAppServerClient: Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    func readRateLimits(at executablePath: String) async throws -> CodexRateLimitReadResult {
        let process = Process()
        let input = Pipe()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw CodexAppServerError.launchFailed
        }

        defer {
            input.fileHandleForWriting.closeFile()
            output.fileHandleForReading.closeFile()
            if process.isRunning {
                process.terminate()
            }
        }

        return try await withThrowingTaskGroup(of: CodexRateLimitReadResult.self) { group in
            group.addTask {
                try await readResponse(
                    input: input.fileHandleForWriting,
                    output: output.fileHandleForReading
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
                throw CodexAppServerError.timedOut
            }

            guard let result = try await group.next() else {
                throw CodexAppServerError.childExited
            }
            group.cancelAll()
            return result
        }
    }

    private func readResponse(
        input: FileHandle,
        output: FileHandle
    ) async throws -> CodexRateLimitReadResult {
        try write(
            JSONRPCRequest(
                id: 1,
                method: "initialize",
                params: InitializeParameters(
                    clientInfo: ClientInfo(name: "AI Usage", version: "1.0"),
                    capabilities: EmptyParameters()
                )
            ),
            to: input
        )

        var didInitialize = false
        for try await line in output.bytes.lines {
            guard let message = line.data(using: .utf8) else { continue }
            let envelope: JSONRPCResponse
            do {
                envelope = try JSONDecoder().decode(JSONRPCResponse.self, from: message)
            } catch {
                continue
            }

            guard let id = envelope.id?.integerValue else {
                continue
            }

            if id == 1 {
                try throwIfError(envelope.error)
                guard envelope.result != nil else {
                    throw CodexAppServerError.malformedResponse
                }
                try write(JSONRPCNotification(method: "initialized"), to: input)
                try write(
                    JSONRPCRequest(id: 2, method: "account/rateLimits/read", params: NullParameters()),
                    to: input
                )
                didInitialize = true
                continue
            }

            guard id == 2, didInitialize else { continue }
            try throwIfError(envelope.error)
            guard let result = envelope.result else {
                throw CodexAppServerError.malformedResponse
            }
            do {
                return try JSONDecoder().decode(CodexRateLimitReadResult.self, from: result)
            } catch {
                throw CodexAppServerError.malformedResponse
            }
        }

        throw CodexAppServerError.childExited
    }

    private func write(_ request: some Encodable, to input: FileHandle) throws {
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func throwIfError(_ error: JSONRPCError?) throws {
        guard let error else { return }
        if error.code == -32601 {
            throw CodexAppServerError.unsupportedVersion
        }
        let message = error.message.lowercased()
        let isSignedOut = message.contains("login")
            || message.contains("sign in")
            || message.contains("signed in")
            || message.contains("unauthorized")
            || message.contains("authentication")
        if isSignedOut {
            throw CodexAppServerError.signedOut
        }
        throw CodexAppServerError.malformedResponse
    }
}

private struct JSONRPCRequest<Parameters: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: Parameters
}

private struct JSONRPCNotification: Encodable {
    let jsonrpc = "2.0"
    let method: String
}

private struct InitializeParameters: Encodable {
    let clientInfo: ClientInfo
    let capabilities: EmptyParameters
}

private struct ClientInfo: Encodable {
    let name: String
    let version: String
}

private struct EmptyParameters: Codable {}

private struct NullParameters: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

private struct JSONRPCResponse: Decodable {
    let id: JSONRPCID?
    let result: Data?
    let error: JSONRPCError?

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id)
        error = try container.decodeIfPresent(JSONRPCError.self, forKey: .error)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)?.encodedData
    }
}

private enum JSONRPCID: Decodable {
    case integer(Int)
    case string(String)

    var integerValue: Int? {
        if case let .integer(value) = self {
            value
        } else {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
        } else {
            self = try .string(container.decode(String.self))
        }
    }
}

private struct JSONRPCError: Decodable {
    let code: Int?
    let message: String
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    var encodedData: Data? {
        try? JSONEncoder().encode(self)
    }
}

extension JSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = try .array(container.decode([JSONValue].self))
        }
    }
}
