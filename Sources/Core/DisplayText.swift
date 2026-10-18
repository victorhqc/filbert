import Foundation

/// Provider text resolves when it is shown, so a language change needs no refetch.
public struct DisplayText: Sendable {
    private let resolve: @Sendable () -> String

    public init(_ resolve: @escaping @Sendable () -> String) {
        self.resolve = resolve
    }

    public init(verbatim text: String) {
        resolve = { text }
    }

    public init(describing error: any Error) {
        let error = CaughtError(value: error)
        resolve = { error.value.localizedDescription }
    }

    public var resolved: String {
        resolve()
    }
}

/// `any Error` is not Sendable. Filbert never mutates an error after it catches it.
private struct CaughtError: @unchecked Sendable {
    let value: any Error
}
