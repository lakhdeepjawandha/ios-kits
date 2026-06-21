import Foundation

/// A type-safe wrapper over `UserDefaults` with transparent `Codable` support.
///
/// All values are JSON-encoded, giving uniform behaviour across every `Codable` type
/// including `String`, `Int`, `Bool`, `Double`, custom structs, and arrays:
///
/// ```swift
/// var store = KeyValueStore()
/// try store.set(42, for: "launchCount")
/// let count: Int? = store.get("launchCount")
/// ```
///
/// ```swift
/// struct Prefs: Codable { var darkMode: Bool }
/// try store.set(Prefs(darkMode: true), for: "prefs")
/// let prefs: Prefs? = store.get("prefs")
/// ```
public struct KeyValueStore {

    private let defaults: UserDefaults

    /// Create a store backed by the supplied `UserDefaults` suite.
    ///
    /// - Parameter defaults: Defaults to `.standard`; pass a custom suite or an
    ///   ephemeral instance (via ``KeyValueStore/ephemeral()``) for tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Read / Write

    /// Decode a value previously stored with ``set(_:for:)``.
    ///
    /// - Parameters:
    ///   - key: The storage key.
    ///   - type: The expected type; usually inferred from context.
    /// - Returns: The decoded value, or `nil` if the key is absent or decoding fails.
    public func get<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// JSON-encode `value` and persist it under `key`.
    ///
    /// All `Codable` types are supported, including `String`, `Int`, `Bool`,
    /// `Double`, custom `Codable` structs, and collections.
    ///
    /// - Throws: `EncodingError` if the value cannot be serialised.
    public func set<T: Encodable>(_ value: T, for key: String) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key)
    }

    // MARK: - Removal

    /// Remove the value stored under `key`.
    public func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    /// Remove all keys that share the supplied prefix, useful for clearing a feature's settings.
    public func removeAll(withPrefix prefix: String) {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { defaults.removeObject(forKey: $0) }
    }
}

// MARK: - Test / preview helpers

public extension KeyValueStore {

    /// An ephemeral store backed by a throw-away `UserDefaults` suite.
    ///
    /// Use in unit tests and Xcode previews to avoid polluting `.standard`:
    ///
    /// ```swift
    /// let store = KeyValueStore.ephemeral()
    /// ```
    static func ephemeral() -> KeyValueStore {
        // A UUID-named suite creates a fresh, isolated defaults domain.
        let suite = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        return KeyValueStore(defaults: suite)
    }
}
