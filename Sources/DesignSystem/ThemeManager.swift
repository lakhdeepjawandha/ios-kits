import Foundation
import Observation
import SwiftUI

// MARK: - Theme manager

/// An observable store for the app's selected ``ThemePreset`` that persists the choice to
/// `UserDefaults` and exposes the resulting ``Theme``.
///
/// The manager works in terms of ``ThemePreset`` values — the selection is persisted by the
/// preset's stable name (its `rawValue`), so it survives app launches without any external
/// persistence layer. Inject it and its theme into a view tree with ``SwiftUICore/View/themed(_:)``:
///
/// ```swift
/// @State private var themeManager = ThemeManager()
///
/// var body: some Scene {
///     WindowGroup {
///         RootView()
///             .themed(themeManager)
///     }
/// }
/// ```
///
/// Descendants read the live ``Theme`` via `@Environment(\.theme)` and can switch it by
/// reading the manager from the environment and calling ``select(_:)``.
@MainActor
@Observable
public final class ThemeManager {
    /// The currently selected preset. Setting it via ``select(_:)`` persists the change.
    public private(set) var preset: ThemePreset

    /// The active ``Theme`` derived from the selected ``preset``.
    public var theme: Theme { preset.theme }

    /// All presets available for selection, suitable for building a theme picker.
    public var availableThemes: [ThemePreset] { ThemePreset.allCases }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String

    /// Creates a theme manager, restoring any previously persisted selection.
    /// - Parameters:
    ///   - default: The preset to use when nothing valid is persisted. Defaults to ``ThemePreset/fintechNavy``.
    ///   - defaults: The `UserDefaults` store to persist to. Defaults to `.standard`; inject an
    ///     ephemeral suite in tests.
    ///   - storageKey: The key under which the preset name is stored.
    public init(
        default preset: ThemePreset = .fintechNavy,
        defaults: UserDefaults = .standard,
        storageKey: String = "DesignSystem.selectedTheme"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let raw = defaults.string(forKey: storageKey),
           let stored = ThemePreset(rawValue: raw) {
            self.preset = stored
        } else {
            self.preset = preset
        }
    }

    /// Selects a new preset and persists it to `UserDefaults`.
    /// - Parameter preset: The preset to make active.
    public func select(_ preset: ThemePreset) {
        self.preset = preset
        defaults.set(preset.rawValue, forKey: storageKey)
    }
}

// MARK: - View injection

public extension View {
    /// Injects a ``ThemeManager`` and its current ``Theme`` into the environment.
    ///
    /// The view tree re-renders whenever the manager's selection changes, so themed
    /// components pick up the new palette automatically.
    /// - Parameter manager: The theme manager to provide to descendants.
    func themed(_ manager: ThemeManager) -> some View {
        modifier(ThemedModifier(manager: manager))
    }
}

private struct ThemedModifier: ViewModifier {
    // `@Observable` ⇒ `body` re-runs when `manager.theme` changes.
    let manager: ThemeManager

    func body(content: Content) -> some View {
        content
            .environment(manager)
            .environment(\.theme, manager.theme)
    }
}
