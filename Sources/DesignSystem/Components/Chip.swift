import SwiftUI

// MARK: - Chip style

/// Visual style for a ``Chip``.
public enum ChipStyle {
    /// Filled background with accent colour.
    case filled
    /// Outlined with no background fill.
    case outlined
    /// Tinted — light fill using the accent tint.
    case tinted
}

// MARK: - Chip / Badge

/// A compact label used for tags, statuses, and categorical filters.
///
/// ```swift
/// Chip("Equity", style: .tinted)
/// Chip("LIVE", style: .filled)
/// ```
public struct Chip: View {
    @Environment(\.theme) private var theme

    private let label: String
    private let style: ChipStyle
    private let icon: String?

    /// Creates a chip.
    /// - Parameters:
    ///   - label: The text label.
    ///   - style: Visual appearance. Defaults to ``ChipStyle/tinted``.
    ///   - icon: Optional leading SF Symbol name.
    public init(_ label: String, style: ChipStyle = .tinted, icon: String? = nil) {
        self.label = label
        self.style = style
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: DS.FontSize.caption, weight: .semibold))
            }
            Text(label)
                .dsCaption()
                .fontWeight(.semibold)
        }
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.xs)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: Capsule())
        .overlay(Capsule().stroke(borderColor, lineWidth: style == .outlined ? 1.5 : 0))
    }

    private var foregroundColor: Color {
        switch style {
        case .filled:   return .white
        case .outlined: return theme.accent
        case .tinted:   return theme.accent
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .filled:   return theme.accent
        case .outlined: return .clear
        case .tinted:   return theme.accent.opacity(0.15)
        }
    }

    private var borderColor: Color { theme.accent }
}

#Preview("Chip / Badge") {
    let theme = ThemePreset.fintechNavy.theme
    return VStack(spacing: DS.Spacing.md) {
        HStack(spacing: DS.Spacing.sm) {
            Chip("Equity", style: .tinted)
            Chip("LIVE", style: .filled, icon: "circle.fill")
            Chip("ETF", style: .outlined)
        }
        HStack(spacing: DS.Spacing.sm) {
            Chip("Growth", style: .tinted, icon: "arrow.up.right")
            Chip("Crypto")
        }
    }
    .padding()
    .dsTheme(theme)
    .background(theme.background)
}
