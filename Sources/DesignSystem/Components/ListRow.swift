import SwiftUI

/// A standard two-line list row with an optional leading icon and trailing value.
///
/// ```swift
/// ListRow(icon: "chart.line.uptrend.xyaxis", title: "AAPL", subtitle: "Apple Inc.", value: "$189.30", valueColor: theme.positive)
/// ```
public struct ListRow: View {
    @Environment(\.theme) private var theme

    private let icon: String?
    private let title: String
    private let subtitle: String?
    private let value: String?
    private let valueColor: Color?

    /// Creates a list row.
    /// - Parameters:
    ///   - icon: SF Symbol name for the leading icon (optional).
    ///   - title: Primary label.
    ///   - subtitle: Secondary label (optional).
    ///   - value: Trailing value string (optional).
    ///   - valueColor: Colour applied to the trailing value; defaults to `textPrimary`.
    public init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        valueColor: Color? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.valueColor = valueColor
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: DS.FontSize.title, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dsBody()
                    .foregroundStyle(theme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .dsCaption()
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Spacer()

            if let value {
                Text(value)
                    .dsBody()
                    .fontWeight(.semibold)
                    .foregroundStyle(valueColor ?? theme.textPrimary)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }
}

#Preview("List Row") {
    VStack(spacing: 0) {
        ListRow(icon: "chart.line.uptrend.xyaxis", title: "AAPL", subtitle: "Apple Inc.", value: "+2.4%", valueColor: ThemePreset.fintechNavy.theme.positive)
        Divider().padding(.leading, 68)
        ListRow(icon: "bitcoinsign.circle", title: "BTC", subtitle: "Bitcoin", value: "-1.1%", valueColor: ThemePreset.fintechNavy.theme.negative)
        Divider().padding(.leading, 68)
        ListRow(title: "Cash", value: "$4,200")
    }
    .dsTheme(ThemePreset.fintechNavy.theme)
    .background(ThemePreset.fintechNavy.theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    .padding()
    .background(ThemePreset.fintechNavy.theme.background)
}
