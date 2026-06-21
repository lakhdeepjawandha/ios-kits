import SwiftUI

// MARK: - Design tokens

/// Namespace for all primitive design tokens.
///
/// Semantic colours live in ``Theme``; everything else (spacing, radius, typography, shadow,
/// animation) lives here so components stay consistent when they can't read the environment.
public enum DS {

    // MARK: Spacing

    /// 4-pt-based spacing scale.
    public enum Spacing {
        /// 4 pt — tight icon padding, hairline gaps.
        public static let xs: CGFloat = 4
        /// 8 pt — small insets, close groupings.
        public static let sm: CGFloat = 8
        /// 16 pt — default padding / margins.
        public static let md: CGFloat = 16
        /// 24 pt — section spacing.
        public static let lg: CGFloat = 24
        /// 40 pt — hero / page-level breathing room.
        public static let xl: CGFloat = 40
    }

    // MARK: Radius

    /// Corner-radius scale.
    public enum Radius {
        /// 8 pt — chips, small tags.
        public static let sm: CGFloat = 8
        /// 14 pt — cards, buttons.
        public static let md: CGFloat = 14
        /// 22 pt — sheets, large containers.
        public static let lg: CGFloat = 22
        /// Full pill / capsule.
        public static let pill: CGFloat = 9_999
    }

    // MARK: Font sizes (raw)

    /// Raw font-size values. Prefer the ``Typography`` view modifiers in practice.
    public enum FontSize {
        /// 12 pt — overlines, footnotes.
        public static let overline: CGFloat = 12
        /// 13 pt — captions, secondary metadata.
        public static let caption: CGFloat = 13
        /// 15 pt — subheadline / supporting copy.
        public static let subheadline: CGFloat = 15
        /// 17 pt — body / default prose.
        public static let body: CGFloat = 17
        /// 20 pt — callout numbers.
        public static let callout: CGFloat = 20
        /// 22 pt — section titles.
        public static let title: CGFloat = 22
        /// 28 pt — page titles.
        public static let title2: CGFloat = 28
        /// 34 pt — large display numbers.
        public static let largeTitle: CGFloat = 34
        /// 48 pt — hero / metric display.
        public static let display: CGFloat = 48
    }

    // MARK: Shadow

    /// Box-shadow tokens expressed as individual components.
    public enum Shadow {
        /// Subtle — card lifts.
        public static let smColor: Color = .black.opacity(0.06)
        public static let smRadius: CGFloat = 6
        public static let smY: CGFloat = 2

        /// Medium — floating panels.
        public static let mdColor: Color = .black.opacity(0.10)
        public static let mdRadius: CGFloat = 14
        public static let mdY: CGFloat = 6

        /// Large — sheets / overlays.
        public static let lgColor: Color = .black.opacity(0.16)
        public static let lgRadius: CGFloat = 28
        public static let lgY: CGFloat = 12
    }

    // MARK: Animation durations

    /// Standard animation-duration tokens.
    public enum Animation {
        /// 150 ms — micro-interactions (tap feedback).
        public static let fast: Double = 0.15
        /// 250 ms — state transitions (expand / collapse).
        public static let standard: Double = 0.25
        /// 400 ms — page-level, emphasis animations.
        public static let slow: Double = 0.40

        /// Default spring used for interactive elements.
        public static let spring: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.75)
    }
}

// MARK: - Typography view modifiers

public extension View {
    /// Large-title style — 34 pt, bold. Use for screen headings.
    func dsLargeTitle() -> some View { modifier(DSLargeTitleModifier()) }

    /// Title style — 22 pt, semibold. Use for section headings.
    func dsTitle() -> some View { modifier(DSTitleModifier()) }

    /// Title2 style — 28 pt, semibold. Use for page-level sub-headings.
    func dsTitle2() -> some View { modifier(DSTitle2Modifier()) }

    /// Body style — 17 pt, regular. Default prose.
    func dsBody() -> some View { modifier(DSBodyModifier()) }

    /// Subheadline style — 15 pt, medium. Supporting copy, labels.
    func dsSubheadline() -> some View { modifier(DSSubheadlineModifier()) }

    /// Caption style — 13 pt, regular. Metadata, timestamps.
    func dsCaption() -> some View { modifier(DSCaptionModifier()) }

    /// Overline style — 12 pt, semibold, uppercased. Section labels.
    func dsOverline() -> some View { modifier(DSOverlineModifier()) }

    /// Display / metric style — 48 pt, bold. Hero numbers.
    func dsDisplay() -> some View { modifier(DSDisplayModifier()) }
}

// MARK: Private modifiers

private struct DSLargeTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: DS.FontSize.largeTitle, weight: .bold, design: .default))
    }
}

private struct DSTitle2Modifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: DS.FontSize.title2, weight: .semibold))
    }
}

private struct DSTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: DS.FontSize.title, weight: .semibold))
    }
}

private struct DSBodyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: DS.FontSize.body, weight: .regular))
    }
}

private struct DSSubheadlineModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: DS.FontSize.subheadline, weight: .medium))
    }
}

private struct DSCaptionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: DS.FontSize.caption, weight: .regular))
    }
}

private struct DSOverlineModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DS.FontSize.overline, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.8)
    }
}

private struct DSDisplayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: DS.FontSize.display, weight: .bold, design: .rounded))
    }
}
