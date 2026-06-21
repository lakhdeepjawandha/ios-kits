import SwiftUI

/// A view modifier that shows its content only when the user has an active Pro entitlement,
/// otherwise substituting a "locked" view (typically a ``PaywallView``).
///
/// Apply it with ``SwiftUI/View/requiresPro(_:onLocked:)``. Because ``SubscriptionManager`` is
/// `@Observable`, the gate flips automatically the moment ``SubscriptionManager/hasPro`` changes
/// (e.g. right after a successful purchase or restore).
public struct ProGate<Locked: View>: ViewModifier {
    private let manager: SubscriptionManager
    @ViewBuilder private let onLocked: () -> Locked

    /// Create a Pro gate.
    ///
    /// - Parameters:
    ///   - manager: The subscription manager whose entitlement gates the content.
    ///   - onLocked: The view to show when the user is not Pro (e.g. a paywall).
    public init(manager: SubscriptionManager, @ViewBuilder onLocked: @escaping () -> Locked) {
        self.manager = manager
        self.onLocked = onLocked
    }

    public func body(content: Content) -> some View {
        if manager.hasPro {
            content
        } else {
            onLocked()
        }
    }
}

public extension View {
    /// Gate this view behind a Pro entitlement, redirecting to `onLocked` when the user is not Pro.
    ///
    /// ```swift
    /// ProFeatureScreen()
    ///     .requiresPro(manager) {
    ///         PaywallView(manager: manager, configuration: .standard)
    ///     }
    /// ```
    ///
    /// To overlay a paywall instead of replacing the screen, present a sheet from within `onLocked`.
    ///
    /// - Parameters:
    ///   - manager: The subscription manager whose entitlement gates the content.
    ///   - onLocked: The view shown when the user is not Pro.
    func requiresPro<Locked: View>(_ manager: SubscriptionManager,
                                   @ViewBuilder onLocked: @escaping () -> Locked) -> some View {
        modifier(ProGate(manager: manager, onLocked: onLocked))
    }

    /// Gate this view behind a Pro entitlement, showing a ``PaywallView`` built from `configuration`
    /// when the user is not Pro.
    ///
    /// - Parameters:
    ///   - manager: The subscription manager whose entitlement gates the content.
    ///   - configuration: Paywall copy and options.
    func requiresPro(_ manager: SubscriptionManager,
                     paywall configuration: PaywallConfiguration) -> some View {
        requiresPro(manager) { PaywallView(manager: manager, configuration: configuration) }
    }
}
