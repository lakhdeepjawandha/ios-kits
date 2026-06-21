import SwiftUI

// MARK: - Progress clamping

/// Internal helpers shared by the determinate progress indicators.
enum DSProgress {
    /// Clamps a raw progress value into the inclusive range `0...1`.
    ///
    /// Non-finite input (`NaN`, `±infinity`) collapses to `0` so the indicators never
    /// render an undefined fill.
    /// - Parameter value: The raw, possibly out-of-range progress.
    /// - Returns: A value guaranteed to be within `0...1`.
    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

// MARK: - Linear progress bar

/// A themed, determinate linear progress bar.
///
/// Progress is expressed as a fraction in `0...1` and is clamped automatically, so passing
/// out-of-range values (e.g. `1.4` or `-0.2`) is safe. Changes animate with the design
/// system's standard spring.
///
/// ```swift
/// ProgressBar(progress: downloadFraction)
/// ```
public struct ProgressBar: View {
    @Environment(\.theme) private var theme

    private let progress: Double
    private let height: CGFloat

    /// Creates a linear progress bar.
    /// - Parameters:
    ///   - progress: Completion fraction in `0...1`. Out-of-range values are clamped.
    ///   - height: The bar's thickness in points. Defaults to `8`.
    public init(progress: Double, height: CGFloat = 8) {
        self.progress = progress
        self.height = height
    }

    /// The `progress` value clamped into `0...1`.
    var clampedProgress: Double { DSProgress.clamp(progress) }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.separator)

                Capsule(style: .continuous)
                    .fill(theme.accent)
                    .frame(width: geo.size.width * clampedProgress)
            }
        }
        .frame(height: height)
        .animation(DS.Animation.spring, value: clampedProgress)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(clampedProgress * 100)) percent"))
    }
}

// MARK: - Circular progress

/// A themed, determinate circular (ring) progress indicator.
///
/// Progress is expressed as a fraction in `0...1` and is clamped automatically. The ring
/// fills clockwise from the top and animates with the design system's standard spring.
///
/// ```swift
/// CircularProgress(progress: uploadFraction)
/// ```
public struct CircularProgress: View {
    @Environment(\.theme) private var theme

    private let progress: Double
    private let lineWidth: CGFloat
    private let size: CGFloat

    /// Creates a circular progress indicator.
    /// - Parameters:
    ///   - progress: Completion fraction in `0...1`. Out-of-range values are clamped.
    ///   - lineWidth: The ring's stroke width in points. Defaults to `8`.
    ///   - size: The diameter of the ring in points. Defaults to `56`.
    public init(progress: Double, lineWidth: CGFloat = 8, size: CGFloat = 56) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.size = size
    }

    /// The `progress` value clamped into `0...1`.
    var clampedProgress: Double { DSProgress.clamp(progress) }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(theme.separator, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    theme.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(DS.Animation.spring, value: clampedProgress)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(clampedProgress * 100)) percent"))
    }
}

// MARK: - Previews

#Preview("Progress Bar") {
    let theme = ThemePreset.fintechNavy.theme
    return VStack(alignment: .leading, spacing: DS.Spacing.lg) {
        ProgressBar(progress: 0)
        ProgressBar(progress: 0.35)
        ProgressBar(progress: 0.7, height: 12)
        ProgressBar(progress: 1.4) // clamped to 1.0
    }
    .padding()
    .dsTheme(theme)
    .background(theme.background)
}

#Preview("Circular Progress") {
    let theme = ThemePreset.fintechNavy.theme
    return HStack(spacing: DS.Spacing.lg) {
        CircularProgress(progress: 0.0)
        CircularProgress(progress: 0.35)
        CircularProgress(progress: 0.75, lineWidth: 10, size: 72)
        CircularProgress(progress: 1.4) // clamped to 1.0
    }
    .padding()
    .dsTheme(theme)
    .background(theme.background)
}
