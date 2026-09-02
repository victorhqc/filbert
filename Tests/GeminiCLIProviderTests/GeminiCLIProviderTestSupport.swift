import Core
import Foundation
@testable import GeminiCLIProvider
import XCTest

struct GeminiHTTPStatusCase {
    let status: Int
    let expected: GeminiCLIError
    let attempts: Int
}

extension GeminiCLIProviderTests {
    func validCredentials() -> GeminiCredentials {
        GeminiCredentials(
            accessToken: "access-token",
            refreshToken: nil,
            expiresAt: Date(timeIntervalSince1970: 10000)
        )
    }

    func makeProvider(
        credentials: GeminiCredentials?,
        transport: RecordingTransport = RecordingTransport(responses: []),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) },
        workflowTimeout: TimeInterval = 90,
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) -> GeminiCLIProvider {
        makeProvider(
            credentialsResult: .success(credentials),
            transport: transport,
            now: now,
            workflowTimeout: workflowTimeout,
            sleep: sleep
        )
    }

    func makeProvider(
        credentialsResult: Result<GeminiCredentials?, GeminiCredentialError>,
        transport: RecordingTransport = RecordingTransport(responses: []),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) },
        workflowTimeout: TimeInterval = 90,
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) -> GeminiCLIProvider {
        let http = GeminiHTTPClient(transport: transport, sleep: sleep ?? { _ in })
        return GeminiCLIProvider(
            credentialStore: StubCredentialStore(result: credentialsResult),
            oauth: GeminiOAuthClient(http: http),
            codeAssist: GeminiCodeAssistClient(http: http),
            now: now,
            workflowTimeout: workflowTimeout
        )
    }

    func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name.replacingOccurrences(of: ".json", with: ""),
                withExtension: "json"
            )
        )
        return try Data(contentsOf: url)
    }

    func decodeFixture<T: Decodable>(
        _ name: String,
        as _: T.Type
    ) throws -> T {
        try JSONDecoder().decode(T.self, from: fixtureData(name))
    }

    func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    func assertLoadCodeAssistRequest(_ request: URLRequest) throws {
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json.keys.sorted(), ["metadata"])
        XCTAssertEqual(
            json["metadata"] as? [String: String],
            [
                "ideType": "IDE_UNSPECIFIED",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI",
            ]
        )
        XCTAssertEqual(
            try canonicalJSON(body),
            try canonicalJSON(fixtureData("load-code-assist-request.json"))
        )
    }
}

private struct StubCredentialStore: GeminiCredentialStore {
    let result: Result<GeminiCredentials?, GeminiCredentialError>

    func load() throws -> GeminiCredentials? {
        try result.get()
    }
}

actor GeminiRequestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

actor GeminiSleepRecorder {
    private var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }

    func recordedValues() -> [TimeInterval] {
        values
    }
}

actor RecordingTransport: GeminiHTTPTransport {
    private var remainingResponses: [GeminiHTTPResponse]
    private var requests: [URLRequest] = []
    private let delay: TimeInterval
    private let gate: GeminiRequestGate?
    private let logger: (any GeminiLogSink)?
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        responses: [GeminiHTTPResponse],
        delay: TimeInterval = 0,
        gate: GeminiRequestGate? = nil,
        logger: (any GeminiLogSink)? = nil
    ) {
        remainingResponses = responses
        self.delay = delay
        self.gate = gate
        self.logger = logger
    }

    func send(_ request: URLRequest) async throws -> GeminiHTTPResponse {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        requests.append(request)
        let satisfied = requestWaiters.filter { requests.count >= $0.0 }
        requestWaiters.removeAll { requests.count >= $0.0 }
        satisfied.forEach { $0.1.resume() }
        if let gate {
            await gate.wait()
        }
        guard !remainingResponses.isEmpty else {
            throw GeminiHTTPError.network
        }
        let response = remainingResponses.removeFirst()
        logger?.requestCompleted(
            statusCode: response.statusCode,
            latencyMilliseconds: 0
        )
        return response
    }

    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

final class RecordingLogSink: GeminiLogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func requestCompleted(statusCode: Int, latencyMilliseconds: Int) {
        lock.lock()
        entries.append("status=\(statusCode) latencyMs=\(latencyMilliseconds)")
        lock.unlock()
    }

    func requestFailed(latencyMilliseconds: Int) {
        lock.lock()
        entries.append("failure latencyMs=\(latencyMilliseconds)")
        lock.unlock()
    }

    func recordedEntries() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

class GeminiHostResponseURLProtocol: URLProtocol {
    static var responseURL: URL?
    static var responseData = Data()
    static var responseStatusCode = 200
    static var responseHeaders: [String: String]?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responseURL = Self.responseURL,
              let response = HTTPURLResponse(
                  url: responseURL,
                  statusCode: Self.responseStatusCode,
                  httpVersion: nil,
                  headerFields: Self.responseHeaders
              )
        else {
            client?.urlProtocol(
                self,
                didFailWithError: GeminiHTTPError.network
            )
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
