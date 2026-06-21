import SwiftUI

/// A centred empty-state illustration with icon, title, message, and optional CTA button.
///
/// ```swift
/// EmptyStateView(
///     icon: "chart.line.downtrend.xyaxis",
///     title: "No Positions Yet",
///     message: "Start by adding your first trade.",
///     cta: ("Add Trade", { showSheet = true })
/// )
/// ```
public struct EmptyStateView: View {
    @Environment(\.theme) private var theme

    private let icon: String
    private let title: String
    private let message: String
    private let cta: (label: String, handler: () -> Void)?

    /// Creates an empty-state view.
    /// - Parameters:
    ///   - icon: SF Symbol name for the illustration.
    ///   - title: Short, encouraging heading.
    ///   - message: Explanatory body copy.
    ///   - cta: Optional call-to-action expressed as `(label, handler)`.
    public init(
        icon: String,
        title: String,
        message: String,
        cta: (label: String, handler: () -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.cta = cta
    }

    public var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.accent.opacity(0.7))
                .padding(DS.Spacing.lg)
                .background(theme.accent.opacity(0.08), in: Circle())

            VStack(spacing: DS.Spacing.sm) {
                Text(title)
                    .dsTitle()
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .dsBody()
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let cta {
                PrimaryButton(cta.label, action: cta.handler)
                    .frame(maxWidth: 260)
            }
        }
        .padding(DS.Spacing.xl)
    }
}

#Preview("Empty State") {
    let theme = ThemePreset.fintechNavy.theme
    return EmptyStateView(
        icon: "chart.line.downtrend.xyaxis",
        title: "No Positions Yet",
        message: "Start by adding your first trade to see your portfolio performance here.",
        cta: ("Add Trade", {})
    )
    .dsTheme(theme)
    .background(theme.background)
}
