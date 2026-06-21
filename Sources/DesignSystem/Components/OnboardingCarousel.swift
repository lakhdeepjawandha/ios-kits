import SwiftUI

// MARK: - Page model

/// A single page in an ``OnboardingCarousel``.
///
/// ```swift
/// OnboardingPage(icon: "lock.shield", title: "Private by design",
///                body: "Your data never leaves your device.")
/// ```
public struct OnboardingPage: Identifiable, Sendable {
    /// Stable identity for `ForEach` diffing.
    public let id = UUID()
    /// SF Symbol name shown above the title.
    public let icon: String
    /// Headline for the page.
    public let title: String
    /// Supporting body copy beneath the title.
    public let body: String

    /// Creates an onboarding page.
    /// - Parameters:
    ///   - icon: SF Symbol name displayed at the top of the page.
    ///   - title: The page headline.
    ///   - body: Supporting description text.
    public init(icon: String, title: String, body: String) {
        self.icon = icon
        self.title = title
        self.body = body
    }
}

// MARK: - Carousel

/// A themed, paged onboarding/intro carousel.
///
/// Drive it with an array of ``OnboardingPage`` values. The carousel renders a page
/// indicator, a **Skip** action (hidden on the final page) and a primary button that
/// advances through the pages — becoming **Get Started** on the last page. Both *Skip*
/// and the final *Get Started* invoke `onComplete`.
///
/// ```swift
/// OnboardingCarousel(pages: pages) {
///     hasCompletedOnboarding = true
/// }
/// ```
public struct OnboardingCarousel: View {
    @Environment(\.theme) private var theme

    private let pages: [OnboardingPage]
    private let onComplete: () -> Void

    @State private var index = 0
    @State private var dragOffset: CGFloat = 0

    /// Creates an onboarding carousel.
    /// - Parameters:
    ///   - pages: The ordered pages to display. An empty array renders nothing.
    ///   - onComplete: Invoked when the user taps **Skip** or finishes the last page.
    public init(pages: [OnboardingPage], onComplete: @escaping () -> Void) {
        self.pages = pages
        self.onComplete = onComplete
    }

    private var isLastPage: Bool { index >= pages.count - 1 }

    public var body: some View {
        if pages.isEmpty {
            Color.clear
        } else {
            VStack(spacing: DS.Spacing.xl) {
                skipRow
                pager
                indicator
                primaryAction
            }
            .padding(DS.Spacing.lg)
            .background(theme.background)
        }
    }

    // MARK: Subviews

    private var skipRow: some View {
        HStack {
            Spacer()
            Button("Skip", action: onComplete)
                .dsBody()
                .foregroundStyle(theme.textSecondary)
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
        }
    }

    private var pager: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                ForEach(pages) { page in
                    pageView(page)
                        .frame(width: width)
                }
            }
            .offset(x: -CGFloat(index) * width + dragOffset)
            .animation(DS.Animation.spring, value: index)
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation.width }
                    .onEnded { value in
                        let threshold = width * 0.25
                        if value.translation.width < -threshold, index < pages.count - 1 {
                            index += 1
                        } else if value.translation.width > threshold, index > 0 {
                            index -= 1
                        }
                        withAnimation(DS.Animation.spring) { dragOffset = 0 }
                    }
            )
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: page.icon)
                .font(.system(size: 72))
                .foregroundStyle(theme.accent)

            VStack(spacing: DS.Spacing.sm) {
                Text(page.title)
                    .dsTitle()
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .dsBody()
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var indicator: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? theme.accent : theme.separator)
                    .frame(width: i == index ? 20 : 8, height: 8)
                    .animation(DS.Animation.spring, value: index)
            }
        }
    }

    private var primaryAction: some View {
        PrimaryButton(isLastPage ? "Get Started" : "Continue") {
            if isLastPage {
                onComplete()
            } else {
                index += 1
            }
        }
    }
}

// MARK: - Preview

#Preview("Onboarding Carousel") {
    let theme = ThemePreset.fintechNavy.theme
    return OnboardingCarousel(
        pages: [
            OnboardingPage(icon: "chart.line.uptrend.xyaxis",
                           title: "Track your portfolio",
                           body: "See every holding update in real time, all in one place."),
            OnboardingPage(icon: "bell.badge",
                           title: "Smart alerts",
                           body: "Get notified the moment a price target is hit."),
            OnboardingPage(icon: "lock.shield",
                           title: "Private by design",
                           body: "Your data is encrypted and never leaves your device."),
        ],
        onComplete: {}
    )
    .dsTheme(theme)
    .background(theme.background)
}
