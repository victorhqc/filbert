@testable import Core
@testable import CursorProvider
import Foundation
import Security
import XCTest

final class CursorExternalAccessorTests: XCTestCase {
    func testBootstrapReadsExternalPairViaSharedAccessor() throws {
        let vault = TestCursorCredentialVault()
        let contexts = LockedBox([ObjectIdentifier]())
        let storage = ClosureKeychainStorage { _, _, context in
            contexts.withValue { $0.append(ObjectIdentifier(context)) }
            return Data("token".utf8)
        }
        let store = CursorTokenStore(
            vault: vault,
            homeDirectory: "/test",
            externalStorage: storage,
            externalContext: .shared,
            readSQLiteValue: { _, _ in nil }
        )

        let pair = try store.loadOrBootstrap()

        XCTAssertEqual(pair?.accessToken, "token")
        XCTAssertEqual(pair?.refreshToken, "token")
        XCTAssertTrue(contexts.read().allSatisfy {
            $0 == ObjectIdentifier(KeychainAuthenticationContext.shared)
        })
    }

    func testBootstrapReusesOneAuthenticationContextAcrossReads() throws {
        let vault = TestCursorCredentialVault()
        let contexts = LockedBox(Set<ObjectIdentifier>())
        let storage = ClosureKeychainStorage { service, _, context in
            _ = contexts.withValue {
                $0.insert(ObjectIdentifier(context))
            }
            return Data((service == "cursor-access-token" ? "access" : "refresh").utf8)
        }
        let store = CursorTokenStore(
            vault: vault,
            homeDirectory: "/test",
            externalStorage: storage,
            externalContext: .shared,
            readSQLiteValue: { _, _ in nil }
        )

        XCTAssertEqual(
            try store.loadOrBootstrap(),
            CursorTokenPair(accessToken: "access", refreshToken: "refresh")
        )
        XCTAssertEqual(contexts.read().count, 1)
    }

    func testKeychainAccessFailureStopsLaterLayoutsAndSQLiteFallback() {
        let vault = TestCursorCredentialVault()
        let keychainServices = LockedBox([String]())
        let sqliteReads = LockedBox(0)
        let storage = ClosureKeychainStorage { service, _, _ in
            keychainServices.withValue { $0.append(service) }
            throw KeychainStorageError.status(errSecAuthFailed)
        }
        let store = CursorTokenStore(
            vault: vault,
            homeDirectory: "/test",
            externalStorage: storage,
            readSQLiteValue: { _, _ in
                sqliteReads.withValue { $0 += 1 }
                return nil
            }
        )

        XCTAssertThrowsError(try store.loadOrBootstrap()) { error in
            XCTAssertEqual(
                error as? CursorExternalCredentialError,
                .keychain(errSecAuthFailed)
            )
        }
        XCTAssertEqual(keychainServices.read(), ["cursor-access-token"])
        XCTAssertEqual(sqliteReads.read(), 0)

        XCTAssertThrowsError(try store.loadOrBootstrap())
        XCTAssertEqual(keychainServices.read(), ["cursor-access-token"])
        XCTAssertEqual(sqliteReads.read(), 0)
    }

    func testAbsentItemIsDistinctFromAuthenticationFailure() throws {
        let vault = TestCursorCredentialVault()
        let storage = ClosureKeychainStorage { _, _, _ in nil }
        let store = CursorTokenStore(
            vault: vault,
            homeDirectory: "/test",
            externalStorage: storage,
            readSQLiteValue: { _, _ in nil }
        )

        // Absence (errSecItemNotFound) is not an error; it falls through to
        // SQLite and ultimately returns nil.
        XCTAssertNil(try store.loadOrBootstrap())
    }

    func testMalformedExternalRecordSurfacesTypedError() {
        let vault = TestCursorCredentialVault()
        let storage = ClosureKeychainStorage { _, _, _ in
            // Non-UTF-8 payload cannot be decoded into a String token.
            Data([0xD0, 0xD0, 0xD0])
        }
        let store = CursorTokenStore(
            vault: vault,
            homeDirectory: "/test",
            externalStorage: storage,
            readSQLiteValue: { _, _ in nil }
        )

        XCTAssertThrowsError(try store.loadOrBootstrap()) { error in
            XCTAssertEqual(
                error as? CursorExternalCredentialError,
                .malformedKeychainRecord
            )
        }
    }
}
