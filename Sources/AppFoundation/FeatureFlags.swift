import Foundation

/// Lightweight local feature-flag store backed by `UserDefaults`.
///
/// Define your flags as static constants on a `FeatureFlags` extension:
/// ```swift
/// extension FeatureFlags {
///     static let darkModeV2 = Flag<Bool>(key: "flag.darkModeV2", default: false)
/// }
/// ```
/// Then read/write via the shared store:
/// ```swift
/// FeatureFlags.shared[FeatureFlags.darkModeV2]        // read
/// FeatureFlags.shared[FeatureFlags.darkModeV2] = true // write
/// ```
public final class FeatureFlags: @unchecked Sendable {
    /// Shared instance backed by `UserDefaults.standard`.
    public static let shared = FeatureFlags()

    private let defaults: UserDefaults

    /// Create a store backed by the given `UserDefaults` suite (default: `.standard`).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Typed flag descriptor

    /// A typed flag descriptor pairing a storage key with a default value.
    public struct Flag<Value: UserDefaultsStorable> {
        /// `UserDefaults` key used for storage.
        public let key: String
        /// Value returned when the key has never been set.
        public let `default`: Value

        public init(key: String, default value: Value) {
            self.key = key
            self.default = value
        }
    }

    // MARK: - Subscript access

    /// Read a flag value.
    public subscript<V: UserDefaultsStorable>(_ flag: Flag<V>) -> V {
        get { V.read(from: defaults, key: flag.key) ?? flag.default }
        set { newValue.write(to: defaults, key: flag.key) }
    }

    /// Reset a flag to its default by removing the stored value.
    public func reset<V: UserDefaultsStorable>(_ flag: Flag<V>) {
        defaults.removeObject(forKey: flag.key)
    }
}

// MARK: - Storage protocol

/// A value type that knows how to read and write itself to `UserDefaults`.
public protocol UserDefaultsStorable {
    static func read(from defaults: UserDefaults, key: String) -> Self?
    func write(to defaults: UserDefaults, key: String)
}

extension Bool: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, key: String) -> Bool? {
        defaults.object(forKey: key).map { _ in defaults.bool(forKey: key) }
    }
    public func write(to defaults: UserDefaults, key: String) {
        defaults.set(self, forKey: key)
    }
}

extension Int: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, key: String) -> Int? {
        defaults.object(forKey: key).map { _ in defaults.integer(forKey: key) }
    }
    public func write(to defaults: UserDefaults, key: String) {
        defaults.set(self, forKey: key)
    }
}

extension Double: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, key: String) -> Double? {
        defaults.object(forKey: key).map { _ in defaults.double(forKey: key) }
    }
    public func write(to defaults: UserDefaults, key: String) {
        defaults.set(self, forKey: key)
    }
}

extension String: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, key: String) -> String? {
        defaults.string(forKey: key)
    }
    public func write(to defaults: UserDefaults, key: String) {
        defaults.set(self, forKey: key)
    }
}
