import Foundation

/// Static accessors for common `Info.plist` values.
public enum AppInfo {
    /// Human-readable version string, e.g. `"1.2.3"`.
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Build number string, e.g. `"42"`.
    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Bundle identifier, e.g. `"com.example.MyApp"`.
    public static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    /// Convenience string combining version and build, e.g. `"1.2.3 (42)"`.
    public static var versionBuild: String { "\(version) (\(build))" }
}
