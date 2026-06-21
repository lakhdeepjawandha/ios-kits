import SwiftUI

// MARK: - Row

/// A single row in a settings screen: a type-erased view paired with light metadata for identity
/// and testing.
///
/// Wrap any of SettingsKit's reusable rows (``ToggleRow``, ``LinkRow``, …) — or your own view —
/// in a `SettingsRow`, then group rows into a ``SettingsSection``.
///
/// ```swift
/// SettingsRow(title: "Notifications") {
///     ToggleRow("Enabled", systemImage: "bell", isOn: $notifications)
/// }
/// ```
public struct SettingsRow: Identifiable {
    /// Stable identity for `ForEach` diffing.
    public let id: UUID
    /// A short title describing the row, used for accessibility and testing. Optional.
    public let title: String?

    let content: AnyView

    /// Creates a settings row wrapping the given view.
    /// - Parameters:
    ///   - id: Stable identity. Defaults to a fresh `UUID`.
    ///   - title: An optional short description, surfaced for accessibility and tests.
    ///   - content: The row's view content.
    public init<Content: View>(
        id: UUID = UUID(),
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.title = title
        self.content = AnyView(content())
    }
}

// MARK: - Section

/// A titled group of ``SettingsRow`` values.
///
/// Compose sections so each app shows only what it needs:
///
/// ```swift
/// SettingsSection(header: "About", footer: "Thanks for using the app.") {
///     SettingsRow { LinkRow("Privacy", url: privacyURL) }
///     SettingsRow { AppInfoFooter() }
/// }
/// ```
public struct SettingsSection: Identifiable {
    /// Stable identity for `ForEach` diffing.
    public let id: UUID
    /// Optional section header text.
    public let header: String?
    /// Optional section footer text.
    public let footer: String?
    /// The rows contained in this section.
    public let rows: [SettingsRow]

    /// Creates a section from an explicit array of rows.
    public init(id: UUID = UUID(), header: String? = nil, footer: String? = nil, rows: [SettingsRow]) {
        self.id = id
        self.header = header
        self.footer = footer
        self.rows = rows
    }

    /// Creates a section using a ``SettingsRowBuilder`` closure.
    public init(
        id: UUID = UUID(),
        header: String? = nil,
        footer: String? = nil,
        @SettingsRowBuilder _ rows: () -> [SettingsRow]
    ) {
        self.init(id: id, header: header, footer: footer, rows: rows())
    }
}

// MARK: - Result builders

/// A result builder for assembling `[SettingsRow]`, with support for `if`/`else` and `for` loops.
@resultBuilder
public enum SettingsRowBuilder {
    public static func buildExpression(_ expression: SettingsRow) -> [SettingsRow] { [expression] }
    public static func buildExpression(_ expression: [SettingsRow]) -> [SettingsRow] { expression }
    public static func buildBlock(_ components: [SettingsRow]...) -> [SettingsRow] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [SettingsRow]?) -> [SettingsRow] { component ?? [] }
    public static func buildEither(first component: [SettingsRow]) -> [SettingsRow] { component }
    public static func buildEither(second component: [SettingsRow]) -> [SettingsRow] { component }
    public static func buildArray(_ components: [[SettingsRow]]) -> [SettingsRow] { components.flatMap { $0 } }
}

/// A result builder for assembling `[SettingsSection]`, with support for `if`/`else` and `for` loops.
@resultBuilder
public enum SettingsSectionBuilder {
    public static func buildExpression(_ expression: SettingsSection) -> [SettingsSection] { [expression] }
    public static func buildExpression(_ expression: [SettingsSection]) -> [SettingsSection] { expression }
    public static func buildBlock(_ components: [SettingsSection]...) -> [SettingsSection] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [SettingsSection]?) -> [SettingsSection] { component ?? [] }
    public static func buildEither(first component: [SettingsSection]) -> [SettingsSection] { component }
    public static func buildEither(second component: [SettingsSection]) -> [SettingsSection] { component }
    public static func buildArray(_ components: [[SettingsSection]]) -> [SettingsSection] { components.flatMap { $0 } }
}

// MARK: - Shared row label

/// A shared label for settings rows: a `Label` when a symbol is supplied, otherwise plain `Text`.
@ViewBuilder
func settingsRowLabel(_ title: String, systemImage: String?) -> some View {
    if let systemImage {
        Label(title, systemImage: systemImage)
    } else {
        Text(title)
    }
}
