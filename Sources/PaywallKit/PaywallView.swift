import SwiftUI
import StoreKit
import DesignSystem

/// A reusable paywall sheet. Pass your products' marketing copy via `features`.
public struct PaywallView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    private let manager: SubscriptionManager
    private let title: String
    private let features: [String]

    public init(manager: SubscriptionManager, title: String, features: [String]) {
        self.manager = manager
        self.title = title
        self.features = features
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text(title).font(.system(size: DS.FontSize.largeTitle, weight: .bold))
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(features, id: \.self) { f in
                    Label(f, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            Spacer()
            ForEach(manager.products) { product in
                PrimaryButton("\(product.displayName) — \(product.displayPrice)") {
                    Task { try? await manager.purchase(product) }
                }
            }
            Button("Restore Purchases") { Task { await manager.restore() } }
                .frame(maxWidth: .infinity)
        }
        .padding(DS.Spacing.lg)
        .task { await manager.load() }
        .onChange(of: manager.hasPro) { _, isPro in if isPro { dismiss() } }
    }
}
