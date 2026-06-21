import SwiftUI

/// A full-width outlined secondary button — use for non-primary actions alongside ``PrimaryButton``.
///
/// ```swift
/// SecondaryButton("Learn More") { showSheet = true }
/// ```
public struct SecondaryButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let action: () -> Void

    /// Creates a secondary button.
    /// - Parameters:
    ///   - title: The button label.
    ///   - action: Closure invoked on tap.
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .dsBody()
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .foregroundStyle(theme.accent.opacity(isEnabled ? 1 : 0.4))
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(theme.accent.opacity(isEnabled ? 1 : 0.4), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: DS.Animation.fast), value: isEnabled)
    }
}

#Preview("Secondary Button") {
    VStack(spacing: DS.Spacing.lg) {
        SecondaryButton("Learn More") {}
        SecondaryButton("Disabled") {}
            .disabled(true)
    }
    .padding()
    .dsTheme(ThemePreset.fintechNavy.theme)
    .background(ThemePreset.fintechNavy.theme.background)
}
