import SwiftUI

/// A full-width, themed primary call-to-action button.
///
/// ```swift
/// PrimaryButton("Get Started") { viewModel.start() }
/// ```
public struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let action: () -> Void

    /// Creates a primary button.
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
                .foregroundStyle(.white)
        }
        .background(
            theme.accent.opacity(isEnabled ? 1 : 0.4),
            in: RoundedRectangle(cornerRadius: DS.Radius.md)
        )
        .animation(.easeInOut(duration: DS.Animation.fast), value: isEnabled)
    }
}

#Preview("Primary Button") {
    VStack(spacing: DS.Spacing.lg) {
        PrimaryButton("Get Started") {}
        PrimaryButton("Disabled") {}
            .disabled(true)
    }
    .padding()
    .dsTheme(ThemePreset.fintechNavy.theme)
    .background(ThemePreset.fintechNavy.theme.background)
}
