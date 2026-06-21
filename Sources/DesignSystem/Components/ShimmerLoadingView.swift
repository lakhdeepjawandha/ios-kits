import SwiftUI

// MARK: - Shimmer effect

/// A shimmer / skeleton-loading effect applied to any view.
///
/// Apply as a modifier to a placeholder shape:
/// ```swift
/// RoundedRectangle(cornerRadius: DS.Radius.sm)
///     .frame(height: 20)
///     .shimmer()
/// ```
public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.45), location: 0.4),
                            .init(color: .clear, location: 0.8),
                        ],
                        startPoint: .init(x: phase - 0.5, y: 0),
                        endPoint: .init(x: phase + 0.5, y: 0)
                    )
                    .frame(width: width * 3)
                    .offset(x: -width + phase * width * 3)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.4).repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

public extension View {
    /// Applies an animated shimmer / skeleton-loading effect to this view.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Convenience skeleton rows

/// A pre-built skeleton placeholder that mimics a ``ListRow``.
public struct ShimmerListRow: View {
    @Environment(\.theme) private var theme

    /// Creates a shimmer list-row placeholder.
    public init() {}

    public var body: some View {
        HStack(spacing: DS.Spacing.md) {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(theme.separator)
                .frame(width: 36, height: 36)
                .shimmer()

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(theme.separator)
                    .frame(width: 120, height: 14)
                    .shimmer()
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(theme.separator)
                    .frame(width: 80, height: 11)
                    .shimmer()
            }

            Spacer()

            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(theme.separator)
                .frame(width: 60, height: 14)
                .shimmer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }
}

/// A pre-built skeleton placeholder that mimics a ``MetricCard``.
public struct ShimmerMetricCard: View {
    @Environment(\.theme) private var theme

    /// Creates a shimmer metric-card placeholder.
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(theme.separator)
                .frame(width: 80, height: 11)
                .shimmer()
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(theme.separator)
                .frame(height: 40)
                .shimmer()
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(theme.separator)
                .frame(width: 60, height: 11)
                .shimmer()
        }
        .padding(DS.Spacing.md)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

#Preview("Shimmer Loading") {
    let theme = ThemePreset.fintechNavy.theme
    return VStack(spacing: DS.Spacing.md) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.md) {
            ShimmerMetricCard()
            ShimmerMetricCard()
        }
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                ShimmerListRow()
                Divider().padding(.leading, DS.Spacing.xl + DS.Spacing.md)
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }
    .padding()
    .dsTheme(theme)
    .background(theme.background)
}
