import Darwin
import Foundation

public struct ErrorLog: Sendable {
    public static let shared = ErrorLog(
        directoryURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Filbert", isDirectory: true)
    )

    public var fileURL: URL {
        directoryURL.appendingPathComponent("errors.log")
    }

    public var availableFileURL: URL? {
        do {
            return try withLockedDirectory(create: false) { directory in
                guard faccessat(directory, ".", W_OK | X_OK, 0) == 0 else { return nil }
                let file = try openFile("errors.log", directory: directory, flags: O_RDWR)
                defer { close(file) }
                let size = try fileSize(file)
                guard size > 0, size <= 1_048_576 else { return nil }
                var byte: UInt8 = 0
                guard read(file, &byte, 1) == 1 else { return nil }
                return fileURL
            }
        } catch {
            return nil
        }
    }

    private let directoryURL: URL
    private let maximumFileSize: Int

    public init(directoryURL: URL, maximumFileSize: Int = 1_048_576) {
        self.directoryURL = directoryURL
        self.maximumFileSize = min(maximumFileSize, 1_048_576)
    }

    @discardableResult
    public func record(
        component: String,
        operation: String,
        code: String,
        providerID: String? = nil,
        error: (any Error)? = nil
    ) -> Bool {
        do {
            let data = try recordData(
                component: component,
                operation: operation,
                code: code,
                providerID: providerID,
                error: error
            )
            guard data.count <= maximumFileSize else { return false }
            try withLockedDirectory(create: true) { directory in
                try append(data, directory: directory)
            }
            return true
        } catch {
            return false
        }
    }
}

private extension ErrorLog {
    struct Record: Encodable {
        let timestamp: String
        let component: String
        let operation: String
        let code: String
        let providerID: String?
        var errorDomain: String?
        var errorCode: Int?
        var decodingFailure: String?
        var causeCode: String?
        var exitStatus: Int32?
        var stdoutBytes: Int?
        var stderrBytes: Int?
        var stdoutTruncated: Bool?
        var cliReportedError: Bool?
        var outputFailure: OutputFailure?
    }

    enum StorageFailure: Error {
        case unavailable
    }

    func recordData(
        component: String,
        operation: String,
        code: String,
        providerID: String?,
        error: (any Error)?
    ) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var record = Record(
            timestamp: formatter.string(from: Date()),
            component: bounded(component),
            operation: bounded(operation),
            code: bounded(code),
            providerID: providerID.map(bounded)
        )
        if let diagnostic = error as? any DiagnosticError {
            record.causeCode = bounded(diagnostic.diagnosticCode)
            if let subprocess = diagnostic.diagnosticSubprocess {
                record.exitStatus = subprocess.exitStatus
                record.stdoutBytes = subprocess.stdoutBytes
                record.stderrBytes = subprocess.stderrBytes
                record.stdoutTruncated = subprocess.stdoutTruncated
                record.cliReportedError = subprocess.cliReportedError
                record.outputFailure = subprocess.outputFailure
            }
        }
        addSafeErrorMetadata(error, to: &record)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(record)
        data.append(0x0A)
        return data
    }

    func addSafeErrorMetadata(_ error: (any Error)?, to record: inout Record) {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .dataCorrupted: record.decodingFailure = "dataCorrupted"
            case .keyNotFound: record.decodingFailure = "keyNotFound"
            case .typeMismatch: record.decodingFailure = "typeMismatch"
            case .valueNotFound: record.decodingFailure = "valueNotFound"
            @unknown default: record.decodingFailure = "unknown"
            }
        } else if let keychainError = error as? KeychainError {
            record.errorDomain = NSOSStatusErrorDomain
            switch keychainError {
            case let .saveFailed(status), let .loadFailed(status), let .deleteFailed(status):
                record.errorCode = Int(status)
            }
        } else if let error {
            let nsError = error as NSError
            let approvedDomains = [
                NSCocoaErrorDomain, NSURLErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain,
            ]
            if approvedDomains.contains(nsError.domain) {
                record.errorDomain = nsError.domain
                record.errorCode = nsError.code
            }
        }
    }

    func bounded(_ value: String) -> String {
        var bytes = Array(value.utf8.prefix(128))
        while !bytes.isEmpty {
            if let prefix = String(bytes: bytes, encoding: .utf8) {
                return prefix
            }
            bytes.removeLast()
        }
        return ""
    }

    func withLockedDirectory<Value>(create: Bool, body: (Int32) throws -> Value) throws -> Value {
        guard directoryURL.isFileURL else { throw StorageFailure.unavailable }
        if create {
            try? FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let directory = open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw StorageFailure.unavailable }
        defer { close(directory) }
        var status = stat()
        guard fstat(directory, &status) == 0, status.st_uid == geteuid(),
              !create || fchmod(directory, 0o700) == 0
        else { throw StorageFailure.unavailable }

        let lock = try openFile(
            "errors.lock",
            directory: directory,
            flags: create ? O_RDWR | O_CREAT : O_RDONLY
        )
        defer { close(lock) }
        let lockOperation = create ? LOCK_EX : LOCK_SH
        while flock(lock, lockOperation) != 0 {
            guard errno == EINTR else { throw StorageFailure.unavailable }
        }
        defer { flock(lock, LOCK_UN) }
        return try body(directory)
    }

    func openFile(_ name: String, directory: Int32, flags: Int32) throws -> Int32 {
        let safeFlags = flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
        let creationFlags = flags & O_CREAT != 0 ? O_EXCL : 0
        var file = openat(directory, name, safeFlags | creationFlags, 0o600)
        if file < 0, errno == EEXIST, flags & O_EXCL == 0 {
            file = openat(directory, name, safeFlags & ~O_CREAT, 0o600)
        }
        guard file >= 0 else { throw StorageFailure.unavailable }
        var status = stat()
        guard fstat(file, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              flags & O_CREAT == 0 || fchmod(file, 0o600) == 0
        else {
            close(file)
            throw StorageFailure.unavailable
        }
        let fileFlags = fcntl(file, F_GETFL)
        guard fileFlags >= 0, fcntl(file, F_SETFL, fileFlags & ~O_NONBLOCK) == 0 else {
            close(file)
            throw StorageFailure.unavailable
        }
        return file
    }

    func fileSize(_ file: Int32) throws -> Int {
        var status = stat()
        guard fstat(file, &status) == 0, status.st_size >= 0,
              let size = Int(exactly: status.st_size)
        else { throw StorageFailure.unavailable }
        return size
    }

    func append(_ data: Data, directory: Int32) throws {
        try boundPreviousFile(directory: directory)
        var file = try openFile("errors.log", directory: directory, flags: O_RDWR | O_CREAT)
        defer { close(file) }
        var size = try fileSize(file)
        if size > maximumFileSize {
            guard ftruncate(file, 0) == 0 else { throw StorageFailure.unavailable }
            size = 0
        }
        if size > maximumFileSize - data.count {
            guard renameat(directory, "errors.log", directory, "errors.log.1") == 0 else {
                throw StorageFailure.unavailable
            }
            close(file)
            file = -1
            file = try openFile("errors.log", directory: directory, flags: O_RDWR | O_CREAT | O_EXCL)
            size = 0
        }
        guard lseek(file, 0, SEEK_END) == size else { throw StorageFailure.unavailable }
        do {
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = write(file, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
                    if written < 0, errno == EINTR {
                        continue
                    }
                    guard written > 0 else { throw StorageFailure.unavailable }
                    offset += written
                }
            }
            guard fsync(file) == 0 else { throw StorageFailure.unavailable }
        } catch {
            _ = ftruncate(file, off_t(size))
            throw error
        }
    }

    func boundPreviousFile(directory: Int32) throws {
        var status = stat()
        guard fstatat(directory, "errors.log.1", &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            guard errno == ENOENT else { throw StorageFailure.unavailable }
            return
        }
        let previous = try openFile("errors.log.1", directory: directory, flags: O_RDWR | O_CREAT)
        defer { close(previous) }
        if try fileSize(previous) > maximumFileSize {
            guard ftruncate(previous, 0) == 0 else { throw StorageFailure.unavailable }
        }
    }
}
