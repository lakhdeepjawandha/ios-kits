import SwiftUI

/// A horizontal section header with an optional trailing action button.
///
/// ```swift
/// SectionHeader("Watchlist", action: ("See All", { navigate() }))
/// ```
public struct SectionHeader: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let action: (label: String, handler: () -> Void)?

    /// Creates a section header.
    /// - Parameters:
    ///   - title: The section title text.
    ///   - action: An optional trailing action expressed as `(label, handler)`.
    public init(_ title: String, action: (label: String, handler: () -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        HStack {
            Text(title)
                .dsOverline()
                .foregroundStyle(theme.textSecondary)

            Spacer()

            if let action {
                Button(action.label, action: action.handler)
                    .dsCaption()
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
    }
}

#Preview("Section Header") {
    VStack(spacing: DS.Spacing.lg) {
        SectionHeader("Recent Activity")
        SectionHeader("Watchlist", action: ("See All", {}))
    }
    .padding()
    .dsTheme(ThemePreset.fintechNavy.theme)
    .background(ThemePreset.fintechNavy.theme.background)
}
