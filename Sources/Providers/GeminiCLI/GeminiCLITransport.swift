import Foundation

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
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
                .flatMap { $0 >= 0 ? min($0, 30) : nil }
            return GeminiHTTPResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                retryAfter: retryAfter
            )
        } catch let error as GeminiHTTPError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GeminiHTTPError.network
        }
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
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw GeminiHTTPError.network
            }
        }
        throw GeminiHTTPError.network
    }
}
