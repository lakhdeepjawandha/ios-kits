import SwiftUI
import DesignSystem
import AppFoundation

/// A footer view showing the app's version, build, and bundle identifier, read from
/// AppFoundation's `AppInfo`.
///
/// Typically placed as the last row/section of a ``SettingsScreen``:
///
/// ```swift
/// AppInfoFooter(appName: "My App")
/// ```
public struct AppInfoFooter: View {
    @Environment(\.theme) private var theme

    private let appName: String?

    /// Creates an app-info footer.
    /// - Parameter appName: Optional app name prefixed before the version. Defaults to `nil`.
    public init(appName: String? = nil) {
        self.appName = appName
    }

    public var body: some View {
        Text(Self.summary(
            appName: appName,
            version: AppInfo.version,
            build: AppInfo.build,
            bundleID: AppInfo.bundleID
        ))
        .font(.system(size: DS.FontSize.caption))
        .foregroundStyle(theme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// Builds the footer's display string from explicit values.
    ///
    /// Pure (takes its inputs rather than reading `Bundle.main`) so the formatting can be
    /// unit-tested deterministically.
    /// - Parameters:
    ///   - appName: Optional app name shown before the version.
    ///   - version: Marketing version string (e.g. `"1.2.3"`).
    ///   - build: Build number string (e.g. `"42"`).
    ///   - bundleID: Bundle identifier.
    /// - Returns: A two-line summary such as `"My App · Version 1.2.3 (42)\ncom.example.app"`.
    public static func summary(appName: String?, version: String, build: String, bundleID: String) -> String {
        let versionLine = "Version \(version) (\(build))"
        if let appName, !appName.isEmpty {
            return "\(appName) · \(versionLine)\n\(bundleID)"
        }
        return "\(versionLine)\n\(bundleID)"
    }
}

#Preview("App Info Footer") {
    let theme = ThemePreset.fintechNavy.theme
    return AppInfoFooter(appName: "Kits Demo")
        .padding()
        .dsTheme(theme)
        .background(theme.background)
}
