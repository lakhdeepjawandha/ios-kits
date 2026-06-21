import SwiftUI

/// A fully themed segmented-control wrapper that matches the active ``Theme``.
///
/// Prefer this over the system `Picker` in `.segmented` style when you need to match the
/// app's palette in dark / custom-coloured contexts.
///
/// ```swift
/// @State private var selected = 0
/// DSSegmentedControl(selection: $selected, segments: ["1D", "1W", "1M", "1Y"])
/// ```
public struct DSSegmentedControl: View {
    @Environment(\.theme) private var theme

    @Binding private var selection: Int
    private let segments: [String]

    /// Creates a segmented control.
    /// - Parameters:
    ///   - selection: Binding to the index of the selected segment.
    ///   - segments: The segment labels in display order.
    public init(selection: Binding<Int>, segments: [String]) {
        self._selection = selection
        self.segments = segments
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(segments.indices, id: \.self) { index in
                segmentButton(index: index)
            }
        }
        .padding(3)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: DS.Radius.sm + 2))
    }

    private func segmentButton(index: Int) -> some View {
        let isSelected = index == selection
        return Button {
            withAnimation(DS.Animation.spring) {
                selection = index
            }
        } label: {
            Text(segments[index])
                .dsCaption()
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm - 2)
        }
        .background(
            isSelected
                ? AnyShapeStyle(theme.accent.opacity(0.20))
                : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: DS.Radius.sm)
        )
    }
}

#Preview("Segmented Control") {
    struct PreviewWrapper: View {
        @State private var selection = 0
        let theme = ThemePreset.fintechNavy.theme

        var body: some View {
            VStack(spacing: DS.Spacing.lg) {
                DSSegmentedControl(selection: $selection, segments: ["1D", "1W", "1M", "3M", "1Y"])
                DSSegmentedControl(selection: $selection, segments: ["Stocks", "Crypto", "ETFs"])
            }
            .padding()
            .dsTheme(theme)
            .background(theme.background)
        }
    }
    return PreviewWrapper()
}
