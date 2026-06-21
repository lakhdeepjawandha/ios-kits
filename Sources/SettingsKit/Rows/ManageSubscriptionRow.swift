import SwiftUI
import PaywallKit

/// A settings row exposing subscription management: opening the system **Manage Subscription**
/// sheet (iOS) and **Restore Purchases**, both driven by PaywallKit's `SubscriptionManager`.
///
/// ```swift
/// ManageSubscriptionRow(manager: subscriptionManager)
/// ```
///
/// On platforms without the manage-subscriptions sheet (e.g. macOS), only the restore action is
/// shown.
public struct ManageSubscriptionRow: View {
    private let manager: SubscriptionManager
    private let manageTitle: String
    private let restoreTitle: String

    @State private var isManagingSubscription = false

    /// Creates a manage-subscription row.
    /// - Parameters:
    ///   - manager: The `SubscriptionManager` whose subscription this row manages and restores.
    ///   - manageTitle: Label for the manage action. Defaults to `"Manage Subscription"`.
    ///   - restoreTitle: Label for the restore action. Defaults to `"Restore Purchases"`.
    public init(
        manager: SubscriptionManager,
        manageTitle: String = "Manage Subscription",
        restoreTitle: String = "Restore Purchases"
    ) {
        self.manager = manager
        self.manageTitle = manageTitle
        self.restoreTitle = restoreTitle
    }

    public var body: some View {
        Group {
            #if os(iOS)
            Button(manageTitle) { isManagingSubscription = true }
            #endif
            Button(restoreTitle) { Task { await manager.restore() } }
        }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        #endif
    }
}

#Preview("Manage Subscription Row") {
    Form {
        ManageSubscriptionRow(manager: SubscriptionManager(productIDs: ["pro.yearly"]))
    }
}
