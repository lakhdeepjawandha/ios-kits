import SwiftUI

/// A settings row presenting a tappable `Button` that runs an action.
///
/// Use the `role` parameter for destructive actions (e.g. sign out / delete account):
///
/// ```swift
/// ButtonRow("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
///     session.signOut()
/// }
/// ```
public struct ButtonRow: View {
    private let title: String
    private let systemImage: String?
    private let role: ButtonRole?
    private let action: () -> Void

    /// Creates a button row.
    /// - Parameters:
    ///   - title: The button's label.
    ///   - systemImage: Optional SF Symbol shown before the label.
    ///   - role: Optional button role, e.g. `.destructive`.
    ///   - action: The closure run when tapped.
    public init(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            settingsRowLabel(title, systemImage: systemImage)
        }
    }
}

#Preview("Button Row") {
    Form {
        ButtonRow("Rate the App", systemImage: "star") {}
        ButtonRow("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {}
    }
}
