import Foundation
import Network

public enum NetworkPathStatus: String, Sendable, Equatable, Encodable {
    case satisfied
    case unsatisfied
}

public protocol NetworkPathObserving: AnyObject, Sendable {
    var status: NetworkPathStatus { get }
    /// Yields each status change after the call, never the current status.
    func statusChanges() -> AsyncStream<NetworkPathStatus>
}

public final class SystemNetworkPathObserver: NetworkPathObserving, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    // Treated as online until the monitor's first update so launch fetches run.
    private var currentStatus = NetworkPathStatus.satisfied
    private var continuations: [UUID: AsyncStream<NetworkPathStatus>.Continuation] = [:]

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.publish(path.status == .satisfied ? .satisfied : .unsatisfied)
        }
        monitor.start(queue: DispatchQueue(label: "com.victorhqc.filbert.network-path"))
    }

    deinit {
        monitor.cancel()
        let continuations = lock.withLock { self.continuations.values }
        for continuation in continuations {
            continuation.finish()
        }
    }

    public var status: NetworkPathStatus {
        lock.withLock { currentStatus }
    }

    public func statusChanges() -> AsyncStream<NetworkPathStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<NetworkPathStatus>.makeStream()
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        lock.withLock { continuations[id] = continuation }
        return stream
    }

    private func publish(_ status: NetworkPathStatus) {
        let continuations: [AsyncStream<NetworkPathStatus>.Continuation]? = lock.withLock {
            guard currentStatus != status else { return nil }
            currentStatus = status
            return Array(self.continuations.values)
        }
        for continuation in continuations ?? [] {
            continuation.yield(status)
        }
    }
}
