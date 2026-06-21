import SwiftUI

/// A themed surface container with a subtle shadow lift.
///
/// ```swift
/// Card {
///     Text("Portfolio value")
///         .dsBody()
/// }
/// ```
public struct Card<Content: View>: View {
    @Environment(\.theme) private var theme

    private let content: Content

    /// Creates a card wrapping arbitrary content.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(DS.Spacing.md)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .shadow(color: DS.Shadow.smColor, radius: DS.Shadow.smRadius, y: DS.Shadow.smY)
    }
}

#Preview("Card") {
    Card {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Holdings").dsTitle()
            Text("Updated just now").dsCaption()
        }
    }
    .padding()
    .dsTheme(ThemePreset.fintechNavy.theme)
    .background(ThemePreset.fintechNavy.theme.background)
}
