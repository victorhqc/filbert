import Core
import Foundation

final class ViewModelKeychainStorage: KeychainStorage, @unchecked Sendable {
    var data: Data?
    var shouldFailWrites = false

    func readData(
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws -> Data? {
        data
    }

    func replaceData(
        _ data: Data,
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws {
        if shouldFailWrites {
            throw KeychainStorageError.status(-1)
        }
        self.data = data
    }

    func delete(
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) {}
}
