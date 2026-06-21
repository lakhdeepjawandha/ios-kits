import SwiftUI
import DesignSystem

/// A settings row that lets the user pick the active theme, driven by DesignSystem's
/// `ThemeManager`.
///
/// Selecting a preset calls `ThemeManager.select(_:)`, which persists the choice and updates any
/// view tree injected with `.themed(_:)`.
///
/// ```swift
/// ThemePickerRow(manager: themeManager)
/// ```
public struct ThemePickerRow: View {
    private let title: String
    private let manager: ThemeManager

    /// Creates a theme-picker row.
    /// - Parameters:
    ///   - title: The picker's label. Defaults to `"Theme"`.
    ///   - manager: The `ThemeManager` whose selection this row reads and writes.
    public init(_ title: String = "Theme", manager: ThemeManager) {
        self.title = title
        self.manager = manager
    }

    public var body: some View {
        Picker(title, selection: Binding(
            get: { manager.preset },
            set: { manager.select($0) }
        )) {
            ForEach(manager.availableThemes, id: \.self) { preset in
                Text(preset.displayName).tag(preset)
            }
        }
    }
}

#Preview("Theme Picker Row") {
    @Previewable @State var manager = ThemeManager()
    return Form {
        ThemePickerRow(manager: manager)
    }
    .themed(manager)
}
