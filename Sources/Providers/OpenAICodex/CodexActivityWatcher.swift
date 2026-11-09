import CoreServices
import Foundation

/// Uses FSEvents with file-level events because a vnode source on the
/// directory stays silent when `touch` updates a file that already exists.
enum CodexActivityWatcher {
    static func signals(for fileURL: URL, latency: TimeInterval = 1) -> AsyncStream<Date> {
        AsyncStream { continuation in
            let watcher = FileModificationWatcher(fileURL: fileURL, latency: latency) {
                continuation.yield(Date())
            }
            guard watcher.start() else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in
                watcher.stop()
            }
        }
    }
}

/// `stream` is only touched on `queue`, which also delivers every FSEvents
/// callback, so stopping can never race a callback.
private final class FileModificationWatcher: @unchecked Sendable {
    private let fileURL: URL
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "filbert.codex-activity-watcher")
    private var stream: FSEventStreamRef?
    private var targetPath = ""

    init(fileURL: URL, latency: TimeInterval, onChange: @escaping @Sendable () -> Void) {
        self.fileURL = fileURL
        self.latency = latency
        self.onChange = onChange
    }

    func start() -> Bool {
        queue.sync { startOnQueue() }
    }

    func stop() {
        queue.async { [self] in
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func startOnQueue() -> Bool {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return false
        }
        // FSEvents reports resolved paths, such as `/private/var/...` for a
        // temporary directory, so compare against the resolved directory.
        guard let resolvedDirectory = realpath(directoryURL.path, nil) else { return false }
        defer { free(resolvedDirectory) }
        targetPath = URL(fileURLWithPath: String(cString: resolvedDirectory))
            .appendingPathComponent(fileURL.lastPathComponent)
            .path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileModificationWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            watcher.handle(paths)
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [directoryURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            return false
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    /// One callback carries every event from one latency window, so it
    /// produces at most one signal. A deletion alone produces none.
    private func handle(_ paths: [String]) {
        guard paths.contains(targetPath),
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return
        }
        onChange()
    }
}
