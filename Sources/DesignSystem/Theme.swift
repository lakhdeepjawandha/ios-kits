import SwiftUI

// MARK: - Theme

/// A per-app colour palette. Inject a custom value via `.environment(\.theme, myTheme)` at the
/// root of your view hierarchy.
///
/// Use ``ThemePreset`` for ready-made palettes, or construct your own:
/// ```swift
/// .environment(\.theme, Theme(accent: .indigo, background: .black, …))
/// ```
public struct Theme: Sendable {
    // MARK: Semantic colours

    /// Brand / interactive colour. Buttons, links, highlights.
    public var accent: Color
    /// Page / canvas background.
    public var background: Color
    /// Elevated surface (cards, sheets).
    public var surface: Color
    /// High-emphasis text.
    public var textPrimary: Color
    /// Low-emphasis text, captions, placeholders.
    public var textSecondary: Color
    /// Positive / bullish / success.
    public var positive: Color
    /// Negative / bearish / destructive.
    public var negative: Color
    /// Caution / warning state.
    public var warning: Color
    /// Hairline dividers and separators.
    public var separator: Color

    // MARK: Initialisers

    /// Creates a theme with explicit colours.
    public init(
        accent: Color = .accentColor,
        background: Color = Color(red: 1, green: 1, blue: 1),
        surface: Color = Color(red: 0.95, green: 0.95, blue: 0.97),
        textPrimary: Color = .primary,
        textSecondary: Color = .secondary,
        positive: Color = Color(red: 0.20, green: 0.78, blue: 0.35),
        negative: Color = Color(red: 0.91, green: 0.22, blue: 0.21),
        warning: Color = Color(red: 1.00, green: 0.58, blue: 0.00),
        separator: Color = Color(red: 0.78, green: 0.78, blue: 0.80, opacity: 0.65)
    ) {
        self.accent = accent
        self.background = background
        self.surface = surface
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.positive = positive
        self.negative = negative
        self.warning = warning
        self.separator = separator
    }
}

// MARK: - Environment key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

public extension EnvironmentValues {
    /// The active design-system theme.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View helper

public extension View {
    /// Applies the given theme to this view and all its descendants.
    func dsTheme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
    }
}

// MARK: - Preset palettes

/// Ready-made ``Theme`` palettes you can apply with a single call.
///
/// ```swift
/// .dsTheme(ThemePreset.fintechNavy.theme)
/// ```
public enum ThemePreset: String, CaseIterable, Sendable {
    /// Deep navy with electric blue accents — classic fintech look.
    case fintechNavy = "fintechNavy"
    /// Dark charcoal with neon-green accents — terminal / pro-trader aesthetic.
    case traderDark = "traderDark"
    /// Warm cream with gold accents — premium wealth-management feel.
    case warmGold = "warmGold"

    /// A human-readable name for this preset, suitable for theme pickers and settings UI.
    public var displayName: String {
        switch self {
        case .fintechNavy: return "Fintech Navy"
        case .traderDark:  return "Trader Dark"
        case .warmGold:    return "Warm Gold"
        }
    }

    /// The ``Theme`` value for this preset.
    public var theme: Theme {
        switch self {
        case .fintechNavy:
            return Theme(
                accent: Color(red: 0.22, green: 0.51, blue: 0.96),       // electric blue
                background: Color(red: 0.06, green: 0.09, blue: 0.16),   // deep navy
                surface: Color(red: 0.10, green: 0.14, blue: 0.22),      // mid navy
                textPrimary: .white,
                textSecondary: Color(white: 0.65),
                positive: Color(red: 0.12, green: 0.82, blue: 0.50),
                negative: Color(red: 0.96, green: 0.28, blue: 0.28),
                warning: Color(red: 1.00, green: 0.74, blue: 0.10),
                separator: Color(white: 0.20)
            )
        case .traderDark:
            return Theme(
                accent: Color(red: 0.00, green: 0.90, blue: 0.46),       // neon green
                background: Color(red: 0.08, green: 0.08, blue: 0.08),   // near-black
                surface: Color(red: 0.13, green: 0.13, blue: 0.13),      // dark grey
                textPrimary: Color(red: 0.92, green: 0.92, blue: 0.92),
                textSecondary: Color(white: 0.55),
                positive: Color(red: 0.00, green: 0.90, blue: 0.46),
                negative: Color(red: 1.00, green: 0.27, blue: 0.27),
                warning: Color(red: 1.00, green: 0.68, blue: 0.00),
                separator: Color(white: 0.18)
            )
        case .warmGold:
            return Theme(
                accent: Color(red: 0.78, green: 0.60, blue: 0.22),       // gold
                background: Color(red: 0.97, green: 0.95, blue: 0.90),   // warm cream
                surface: Color(red: 1.00, green: 0.98, blue: 0.94),
                textPrimary: Color(red: 0.13, green: 0.10, blue: 0.05),
                textSecondary: Color(red: 0.45, green: 0.38, blue: 0.25),
                positive: Color(red: 0.16, green: 0.63, blue: 0.35),
                negative: Color(red: 0.80, green: 0.18, blue: 0.18),
                warning: Color(red: 0.85, green: 0.55, blue: 0.00),
                separator: Color(red: 0.82, green: 0.78, blue: 0.70)
            )
        }
    }
}
