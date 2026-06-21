import SwiftUI
import StoreKit
import DesignSystem

/// A reusable, configurable paywall screen.
///
/// Drive its copy and options with a ``PaywallConfiguration``: headline, feature bullets, a
/// highlighted plan, Terms/Privacy links, and the "Manage Subscription" / "Restore" affordances.
/// Each product shows its localized price and, when the user is eligible, its introductory-offer
/// text (e.g. a free trial). The view loads products on appear and dismisses itself once the user
/// becomes Pro.
///
/// ```swift
/// .sheet(isPresented: $showPaywall) {
///     PaywallView(manager: manager, configuration: .init(
///         headline: "Go Pro",
///         features: PaywallConfiguration.Feature.bullets(["Unlimited alerts", "Ad-free"]),
///         highlightedProductID: "pro.yearly"
///     ))
/// }
/// ```
public struct PaywallView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    private let manager: SubscriptionManager
    private let configuration: PaywallConfiguration
    @State private var isManagingSubscription = false

    /// Create a paywall from a configuration.
    ///
    /// - Parameters:
    ///   - manager: The subscription manager backing purchases.
    ///   - configuration: Copy and options for the paywall.
    public init(manager: SubscriptionManager, configuration: PaywallConfiguration) {
        self.manager = manager
        self.configuration = configuration
    }

    /// Convenience initializer mirroring the original simple API: a title and plain-text bullets.
    ///
    /// - Parameters:
    ///   - manager: The subscription manager backing purchases.
    ///   - title: The headline text.
    ///   - features: Plain-text feature bullets.
    public init(manager: SubscriptionManager, title: String, features: [String]) {
        self.init(manager: manager,
                  configuration: PaywallConfiguration(headline: title,
                                                      features: PaywallConfiguration.Feature.bullets(features)))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                header
                if !configuration.features.isEmpty { featureList }
                productList
                footer
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await manager.load() }
        .onChange(of: manager.hasPro) { _, isPro in if isPro { dismiss() } }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(configuration.headline)
                .font(.system(size: DS.FontSize.largeTitle, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            if let subheadline = configuration.subheadline {
                Text(subheadline)
                    .font(.system(size: DS.FontSize.subheadline))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(configuration.features) { feature in
                Label(feature.text, systemImage: feature.systemImage)
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private var productList: some View {
        VStack(spacing: DS.Spacing.md) {
            ForEach(sortedProducts) { product in
                productRow(product)
            }
        }
    }

    @ViewBuilder
    private func productRow(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            PrimaryButton("\(product.displayName) — \(product.displayPrice)") {
                Task { try? await manager.purchase(product) }
            }
            if let introText = introText(for: product) {
                Text(introText)
                    .font(.system(size: DS.FontSize.caption))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, DS.Spacing.xs)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHighlighted(product) { bestValueBadge }
        }
    }

    private var footer: some View {
        VStack(spacing: DS.Spacing.sm) {
            if configuration.showsRestore {
                Button("Restore Purchases") { Task { await manager.restore() } }
                    .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            if configuration.showsManageSubscription {
                Button("Manage Subscription") { isManagingSubscription = true }
                    .frame(maxWidth: .infinity)
            }
            #endif
            legalLinks
            if let footnote = configuration.footnote {
                Text(footnote)
                    .font(.system(size: DS.FontSize.caption))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        if configuration.termsURL != nil || configuration.privacyURL != nil {
            HStack(spacing: DS.Spacing.md) {
                if let terms = configuration.termsURL {
                    Link("Terms of Use", destination: terms)
                }
                if let privacy = configuration.privacyURL {
                    Link("Privacy Policy", destination: privacy)
                }
            }
            .font(.system(size: DS.FontSize.caption))
            .tint(theme.accent)
        }
    }

    private var bestValueBadge: some View {
        Text("Best Value")
            .font(.system(size: DS.FontSize.overline, weight: .semibold))
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(theme.accent, in: Capsule())
            .foregroundStyle(.white)
            .padding(DS.Spacing.xs)
    }

    // MARK: - Helpers

    /// Products with the highlighted plan first, the rest in their loaded order.
    private var sortedProducts: [Product] {
        guard let highlighted = configuration.highlightedProductID else { return manager.products }
        return manager.products.sorted { lhs, _ in lhs.id == highlighted }
    }

    private func isHighlighted(_ product: Product) -> Bool {
        product.id == configuration.highlightedProductID
    }

    /// Intro-offer text, shown only when the user is currently eligible to redeem it.
    private func introText(for product: Product) -> String? {
        guard manager.introEligibleProductIDs.contains(product.id) else { return nil }
        return manager.introOfferDescription(for: product)
    }
}
