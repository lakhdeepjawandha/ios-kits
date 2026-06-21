import Foundation

/// Copy and options that drive a ``PaywallView``.
///
/// ```swift
/// let config = PaywallConfiguration(
///     headline: "Go Pro",
///     subheadline: "Everything, unlocked.",
///     features: PaywallConfiguration.Feature.bullets([
///         "Unlimited watchlists", "Real-time alerts", "Ad-free"
///     ]),
///     highlightedProductID: "pro.yearly",
///     termsURL: URL(string: "https://example.com/terms"),
///     privacyURL: URL(string: "https://example.com/privacy")
/// )
/// ```
public struct PaywallConfiguration: Sendable {

    /// A single feature bullet, with an SF Symbol icon.
    public struct Feature: Identifiable, Sendable, Equatable {
        /// Stable identity for `ForEach`.
        public let id: UUID
        /// The bullet text.
        public var text: String
        /// SF Symbol name shown beside the text.
        public var systemImage: String

        /// Create a feature bullet.
        ///
        /// - Parameters:
        ///   - text: The bullet text.
        ///   - systemImage: SF Symbol name. Default `"checkmark.circle.fill"`.
        ///   - id: Stable identity. Defaults to a fresh `UUID`.
        public init(_ text: String, systemImage: String = "checkmark.circle.fill", id: UUID = UUID()) {
            self.id = id
            self.text = text
            self.systemImage = systemImage
        }

        /// Convenience: turn plain strings into default-icon feature bullets.
        public static func bullets(_ texts: [String]) -> [Feature] {
            texts.map { Feature($0) }
        }
    }

    /// Large headline at the top of the paywall.
    public var headline: String
    /// Optional supporting line beneath the headline.
    public var subheadline: String?
    /// Feature bullets listing what Pro unlocks.
    public var features: [Feature]
    /// Product ID to visually emphasize (e.g. the best-value plan) with a badge and top placement.
    public var highlightedProductID: String?
    /// Optional Terms of Use URL, shown as a link in the footer.
    public var termsURL: URL?
    /// Optional Privacy Policy URL, shown as a link in the footer.
    public var privacyURL: URL?
    /// Whether to show the "Manage Subscription" link (iOS only). Default `true`.
    public var showsManageSubscription: Bool
    /// Whether to show the "Restore Purchases" button. Default `true`.
    public var showsRestore: Bool
    /// Optional fine-print shown beneath the purchase buttons (e.g. auto-renew disclosure).
    public var footnote: String?

    /// Create a paywall configuration.
    ///
    /// - Parameters:
    ///   - headline: Large headline text.
    ///   - subheadline: Optional supporting line.
    ///   - features: Feature bullets.
    ///   - highlightedProductID: Product ID to emphasize.
    ///   - termsURL: Optional Terms of Use URL.
    ///   - privacyURL: Optional Privacy Policy URL.
    ///   - showsManageSubscription: Show the manage-subscription link (iOS). Default `true`.
    ///   - showsRestore: Show the restore button. Default `true`.
    ///   - footnote: Optional fine-print under the buttons.
    public init(headline: String,
                subheadline: String? = nil,
                features: [Feature] = [],
                highlightedProductID: String? = nil,
                termsURL: URL? = nil,
                privacyURL: URL? = nil,
                showsManageSubscription: Bool = true,
                showsRestore: Bool = true,
                footnote: String? = nil) {
        self.headline = headline
        self.subheadline = subheadline
        self.features = features
        self.highlightedProductID = highlightedProductID
        self.termsURL = termsURL
        self.privacyURL = privacyURL
        self.showsManageSubscription = showsManageSubscription
        self.showsRestore = showsRestore
        self.footnote = footnote
    }
}
