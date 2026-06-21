import Foundation
import LocalAuthentication
import Security

/// Errors thrown by ``Keychain`` operations.
public enum KeychainError: Error, Equatable {
    /// The Security framework returned an unexpected `OSStatus`. Inspect the associated value
    /// (e.g. `errSecAuthFailed`, `errSecUserCanceled`, `errSecMissingEntitlement`).
    case unexpectedStatus(OSStatus)
    /// `SecAccessControlCreateWithFlags` failed to build a biometric access-control object.
    case accessControlCreationFailed
    /// A value could not be JSON-encoded for storage.
    case encodingFailed
    /// Stored data could not be JSON-decoded into the requested type.
    case decodingFailed
}

/// Keychain wrapper for tokens and secrets in finance-grade apps.
///
/// Stores items as `kSecClassGenericPassword`, keyed by an account string, optionally scoped to a
/// `service` and `accessGroup`. Every operation surfaces failures as ``KeychainError`` rather than
/// failing silently.
///
/// ## Secure Enclave & what stays on device
/// Keychain item data is encrypted at rest under keys protected by the device passcode and the
/// **Secure Enclave**; the protecting keys never leave the chip. With the default
/// ``Accessibility/whenUnlockedThisDeviceOnly`` (and the other `...ThisDeviceOnly` cases), items
/// are **not** synced to iCloud Keychain and are **not** included in encrypted device backups —
/// they stay on this one device. Nothing here is transmitted off-device.
///
/// - Note: On iOS, items use the modern **data-protection keychain**. On macOS the legacy file
///   keychain is used so the package's unit tests run on an unsigned host; ship finance apps on iOS
///   for the full data-protection guarantees.
/// - Warning: Never log the values you read or write here.
public struct Keychain {

    /// When a keychain item becomes readable, controlling the trade-off between security and
    /// availability. Maps to the `kSecAttrAccessible*` constants.
    public enum Accessibility {
        /// Readable only while the device is unlocked; never leaves this device. **Default.**
        /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
        case whenUnlockedThisDeviceOnly
        /// Readable after the first unlock following a boot (useful for background work); never
        /// leaves this device. (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
        case afterFirstUnlockThisDeviceOnly
        /// Readable only while unlocked **and** only if a device passcode is set; the item is
        /// deleted if the passcode is removed. (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`)
        case whenPasscodeSetThisDeviceOnly

        var cfValue: CFString {
            switch self {
            case .whenUnlockedThisDeviceOnly:     return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenPasscodeSetThisDeviceOnly:  return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            }
        }
    }

    /// Optional service scope (`kSecAttrService`) — namespaces items, e.g. per feature.
    public let service: String?
    /// Optional access group (`kSecAttrAccessGroup`) for sharing items between your apps/extensions.
    public let accessGroup: String?
    /// Accessibility class applied to written items. Defaults to ``Accessibility/whenUnlockedThisDeviceOnly``.
    public let accessibility: Accessibility

    /// Create a Keychain accessor.
    ///
    /// - Parameters:
    ///   - service: Optional `kSecAttrService` namespace for items.
    ///   - accessGroup: Optional keychain access group for cross-app/extension sharing.
    ///   - accessibility: When items become readable. Defaults to the most restrictive sensible
    ///     value for secrets, ``Accessibility/whenUnlockedThisDeviceOnly``.
    public init(service: String? = nil,
                accessGroup: String? = nil,
                accessibility: Accessibility = .whenUnlockedThisDeviceOnly) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    // MARK: - Raw Data API

    /// Store raw data for a key, replacing any existing value (upsert).
    ///
    /// - Parameters:
    ///   - data: The bytes to store. Treat as sensitive; never log it.
    ///   - key: Account key (`kSecAttrAccount`).
    ///   - requireBiometry: When `true`, the item is protected by a `SecAccessControl` with the
    ///     `.biometryCurrentSet` flag — reading it later requires Face ID / Touch ID, and the item
    ///     is **invalidated if the enrolled biometric set changes** (a fingerprint added/removed or
    ///     Face ID re-enrolled), at which point you must re-provision the secret. Because the goal
    ///     is to defeat an attacker who enrolls their own biometric, no device-passcode fallback is
    ///     attached to the item itself.
    /// - Throws: ``KeychainError/accessControlCreationFailed`` or
    ///   ``KeychainError/unexpectedStatus(_:)``.
    public func set(_ data: Data, for key: String, requireBiometry: Bool = false) throws {
        try delete(key)

        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data

        if requireBiometry {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, accessibility.cfValue, .biometryCurrentSet, &error
            ) else {
                throw KeychainError.accessControlCreationFailed
            }
            // Access control supersedes kSecAttrAccessible — do not set both.
            attributes[kSecAttrAccessControl as String] = access
        } else {
            attributes[kSecAttrAccessible as String] = accessibility.cfValue
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Read raw data for a key.
    ///
    /// - Parameters:
    ///   - key: Account key (`kSecAttrAccount`).
    ///   - prompt: Optional message shown in the biometric prompt when the item is biometry-gated.
    ///     Supplied to the read via an `LAContext` (`kSecUseAuthenticationContext`).
    /// - Returns: The stored data, or `nil` if no item exists for the key.
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` for any non-success, non-not-found status
    ///   (including biometric cancellation/failure).
    public func get(_ key: String, prompt: String? = nil) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let prompt {
            let context = LAContext()
            context.localizedReason = prompt
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:      return result as? Data
        case errSecItemNotFound: return nil
        default:                 throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Delete the item for a key. A missing item is treated as success (no-op).
    ///
    /// - Parameter key: Account key (`kSecAttrAccount`).
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` for any status other than success or
    ///   not-found.
    public func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Whether an item exists for the given key (without returning or decrypting its data).
    ///
    /// - Parameter key: Account key (`kSecAttrAccount`).
    /// - Returns: `true` if an item exists.
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` for unexpected statuses.
    public func contains(_ key: String) throws -> Bool {
        var query = baseQuery(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:      return true
        case errSecItemNotFound: return false
        default:                 throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Codable convenience

    /// Store any `Encodable` value as JSON, replacing any existing value (upsert).
    ///
    /// - Parameters:
    ///   - value: The value to encode and store.
    ///   - key: Account key (`kSecAttrAccount`).
    ///   - requireBiometry: See ``set(_:for:requireBiometry:)``.
    /// - Throws: ``KeychainError/encodingFailed`` if encoding fails, plus any error from the
    ///   underlying data write.
    /// - Note: For a value already typed as `Data`, the raw ``set(_:for:requireBiometry:)`` overload
    ///   is selected instead of this generic one.
    public func set<T: Encodable>(_ value: T, for key: String, requireBiometry: Bool = false) throws {
        try set(Self.encode(value), for: key, requireBiometry: requireBiometry)
    }

    /// Read and JSON-decode a value for a key.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - key: Account key (`kSecAttrAccount`).
    ///   - prompt: Optional biometric prompt message for biometry-gated items.
    /// - Returns: The decoded value, or `nil` if no item exists for the key.
    /// - Throws: ``KeychainError/decodingFailed`` if decoding fails, plus any error from the
    ///   underlying data read.
    public func get<T: Decodable>(_ type: T.Type, for key: String, prompt: String? = nil) throws -> T? {
        guard let data = try get(key, prompt: prompt) else { return nil }
        return try Self.decode(type, from: data)
    }

    // MARK: - Internals

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        if let service { query[kSecAttrService as String] = service }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        // On iOS use the modern data-protection keychain. On macOS the legacy file keychain is used
        // so unit tests run on an unsigned host without a keychain-access entitlement.
        #if os(iOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// JSON-encode a value; surfaces failures as ``KeychainError/encodingFailed``.
    /// Exposed internally so the Codable path can be unit-tested without touching the keychain.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try JSONEncoder().encode(value) }
        catch { throw KeychainError.encodingFailed }
    }

    /// JSON-decode data; surfaces failures as ``KeychainError/decodingFailed``.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw KeychainError.decodingFailed }
    }
}
