import XCTest
import LocalAuthentication
@testable import SecurityKit

// MARK: - Keychain round-trip

final class KeychainTests: XCTestCase {
    private let service = "com.test.SecurityKitTests"
    private let key = "round-trip-key"

    private func makeKeychain() -> Keychain { Keychain(service: service) }

    override func tearDownWithError() throws {
        try? makeKeychain().delete(key)
    }

    /// Wraps a keychain call, converting a sandboxed-host "no entitlement" failure into a skip so
    /// the suite still passes in environments without keychain access (e.g. some CI sandboxes).
    private func skippingMissingEntitlement(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch KeychainError.unexpectedStatus(let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain unavailable on this host (errSecMissingEntitlement)")
        }
    }

    func testDataRoundTrip() throws {
        let keychain = makeKeychain()
        let secret = Data("super-secret-token".utf8)

        try skippingMissingEntitlement {
            try keychain.set(secret, for: key)
            XCTAssertEqual(try keychain.get(key), secret)

            try keychain.delete(key)
            XCTAssertNil(try keychain.get(key))
        }
    }

    func testOverwriteKeepsLatestValue() throws {
        let keychain = makeKeychain()

        try skippingMissingEntitlement {
            try keychain.set(Data("first".utf8), for: key)
            try keychain.set(Data("second".utf8), for: key)
            XCTAssertEqual(try keychain.get(key), Data("second".utf8))
        }
    }

    func testGetMissingReturnsNil() throws {
        let keychain = makeKeychain()

        try skippingMissingEntitlement {
            try keychain.delete(key)
            XCTAssertNil(try keychain.get(key))
        }
    }

    func testContains() throws {
        let keychain = makeKeychain()

        try skippingMissingEntitlement {
            try keychain.delete(key)
            XCTAssertFalse(try keychain.contains(key))
            try keychain.set(Data("x".utf8), for: key)
            XCTAssertTrue(try keychain.contains(key))
        }
    }

    func testCodableRoundTrip() throws {
        struct Credentials: Codable, Equatable {
            let username: String
            let pin: Int
        }
        let keychain = makeKeychain()
        let creds = Credentials(username: "ada", pin: 1234)

        try skippingMissingEntitlement {
            try keychain.set(creds, for: key)
            XCTAssertEqual(try keychain.get(Credentials.self, for: key), creds)
        }
    }
}

// MARK: - Codable helpers (no keychain — always runs)

final class KeychainCodableHelperTests: XCTestCase {
    struct Account: Codable, Equatable {
        let id: UUID
        let balance: Double
        let labels: [String]
    }

    func testEncodeDecodeRoundTrip() throws {
        let account = Account(id: UUID(), balance: 42.5, labels: ["checking", "primary"])
        let data = try Keychain.encode(account)
        XCTAssertEqual(try Keychain.decode(Account.self, from: data), account)
    }

    func testDecodeBadDataThrowsDecodingFailed() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try Keychain.decode(Account.self, from: garbage)) { error in
            XCTAssertEqual(error as? KeychainError, .decodingFailed)
        }
    }
}

// MARK: - AppLockManager (injected authenticator + driven dates)

@MainActor
final class AppLockManagerTests: XCTestCase {

    private func makeManager(gracePeriod: TimeInterval = 0,
                             startsLocked: Bool = true,
                             authResult: Bool = true) -> AppLockManager {
        AppLockManager(gracePeriod: gracePeriod,
                       startsLocked: startsLocked,
                       observeLifecycle: false,
                       authenticator: { _ in authResult })
    }

    func testStartsLockedByDefault() {
        XCTAssertTrue(makeManager().isLocked)
    }

    func testUnlockSuccess() async {
        let manager = makeManager(authResult: true)
        let ok = await manager.unlock()
        XCTAssertTrue(ok)
        XCTAssertFalse(manager.isLocked)
    }

    func testUnlockFailureStaysLocked() async {
        let manager = makeManager(authResult: false)
        let ok = await manager.unlock()
        XCTAssertFalse(ok)
        XCTAssertTrue(manager.isLocked)
    }

    func testManualLock() async {
        let manager = makeManager(authResult: true)
        _ = await manager.unlock()
        XCTAssertFalse(manager.isLocked)
        manager.lock()
        XCTAssertTrue(manager.isLocked)
    }

    func testRelocksAfterGraceExceeded() async {
        let manager = makeManager(gracePeriod: 30, authResult: true)
        _ = await manager.unlock()
        XCTAssertFalse(manager.isLocked)

        let t0 = Date()
        manager.applicationDidEnterBackground(at: t0)
        manager.applicationWillEnterForeground(at: t0.addingTimeInterval(31))
        XCTAssertTrue(manager.isLocked, "Should relock after grace period elapses")
    }

    func testStaysUnlockedWithinGrace() async {
        let manager = makeManager(gracePeriod: 30, authResult: true)
        _ = await manager.unlock()

        let t0 = Date()
        manager.applicationDidEnterBackground(at: t0)
        manager.applicationWillEnterForeground(at: t0.addingTimeInterval(5))
        XCTAssertFalse(manager.isLocked, "Should stay unlocked within the grace period")
    }

    func testZeroGraceRelocksImmediately() async {
        let manager = makeManager(gracePeriod: 0, authResult: true)
        _ = await manager.unlock()

        let t0 = Date()
        manager.applicationDidEnterBackground(at: t0)
        manager.applicationWillEnterForeground(at: t0)
        XCTAssertTrue(manager.isLocked)
    }
}

// MARK: - Biometric-gated keychain (skipped on CI / without biometrics)

final class BiometricKeychainTests: XCTestCase {
    func testBiometricItemWritePath() throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Skipping biometric-gated test on CI")
        }
        guard SecurityKit.canAuthenticate() else {
            throw XCTSkip("No enrolled authentication method on this host")
        }

        let keychain = Keychain(service: "com.test.SecurityKitTests.biometric")
        let key = "biometric-key"
        defer { try? keychain.delete(key) }

        // The write itself should not prompt; building the SecAccessControl must succeed.
        do {
            try keychain.set(Data("vault".utf8), for: key, requireBiometry: true)
        } catch KeychainError.unexpectedStatus(let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain unavailable on this host (errSecMissingEntitlement)")
        }
    }
}
