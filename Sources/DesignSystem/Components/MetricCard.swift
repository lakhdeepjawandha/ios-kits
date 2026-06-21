import SwiftUI

/// A card displaying a large metric number with a label and optional delta indicator.
///
/// ```swift
/// MetricCard(value: "$128,450", label: "Portfolio Value", delta: "+3.2%", isPositive: true)
/// ```
public struct MetricCard: View {
    @Environment(\.theme) private var theme

    private let value: String
    private let label: String
    private let delta: String?
    private let isPositive: Bool?
    private let icon: String?

    /// Creates a metric card.
    /// - Parameters:
    ///   - value: The big number / primary value string.
    ///   - label: Descriptive label shown below the value.
    ///   - delta: Optional change string (e.g. "+3.2%", "−$420").
    ///   - isPositive: Whether the delta represents a positive change; controls colour.
    ///   - icon: Optional SF Symbol shown in the top-right corner.
    public init(
        value: String,
        label: String,
        delta: String? = nil,
        isPositive: Bool? = nil,
        icon: String? = nil
    ) {
        self.value = value
        self.label = label
        self.delta = delta
        self.isPositive = isPositive
        self.icon = icon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text(label)
                    .dsCaption()
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: DS.FontSize.subheadline))
                        .foregroundStyle(theme.accent)
                }
            }

            Text(value)
                .dsDisplay()
                .foregroundStyle(theme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if let delta {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: (isPositive ?? true) ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: DS.FontSize.caption, weight: .bold))
                    Text(delta)
                        .dsCaption()
                        .fontWeight(.semibold)
                }
                .foregroundStyle(deltaColor)
            }
        }
        .padding(DS.Spacing.md)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .shadow(color: DS.Shadow.smColor, radius: DS.Shadow.smRadius, y: DS.Shadow.smY)
    }

    private var deltaColor: Color {
        guard let isPositive else { return theme.textSecondary }
        return isPositive ? theme.positive : theme.negative
    }
}

#Preview("Metric Card") {
    let theme = ThemePreset.fintechNavy.theme
    return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.md) {
        MetricCard(value: "$128,450", label: "Portfolio Value", delta: "+3.2%", isPositive: true, icon: "chart.pie")
        MetricCard(value: "14.7%", label: "YTD Return", delta: "−2.1%", isPositive: false)
        MetricCard(value: "23", label: "Positions")
        MetricCard(value: "$4,200", label: "Cash", icon: "banknote")
    }
    .padding()
    .dsTheme(theme)
    .background(theme.background)
}
