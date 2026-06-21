import SwiftUI
import DesignSystem
import PaywallKit

/// A composable settings screen rendered from an array of ``SettingsSection`` values.
///
/// Each app assembles only the sections it wants from SettingsKit's reusable rows (or its own
/// views). Present it inside a `NavigationStack` so ``NavigationLinkRow`` destinations push:
///
/// ```swift
/// NavigationStack {
///     SettingsScreen {
///         SettingsSection(header: "Appearance") {
///             SettingsRow { ThemePickerRow(manager: themeManager) }
///         }
///         SettingsSection {
///             SettingsRow { AppInfoFooter(appName: "My App") }
///         }
///     }
///     .navigationTitle("Settings")
/// }
/// ```
public struct SettingsScreen: View {
    private let sections: [SettingsSection]

    /// Creates a settings screen from an explicit array of sections.
    /// - Parameter sections: The sections to render, in order.
    public init(sections: [SettingsSection]) {
        self.sections = sections
    }

    /// Creates a settings screen using a ``SettingsSectionBuilder`` closure.
    /// - Parameter sections: A builder producing the sections to render.
    public init(@SettingsSectionBuilder _ sections: () -> [SettingsSection]) {
        self.sections = sections()
    }

    public var body: some View {
        Form {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        row.content
                    }
                } header: {
                    if let header = section.header { Text(header) }
                } footer: {
                    if let footer = section.footer { Text(footer) }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Settings Screen") {
    SettingsScreenPreview()
}

/// Holds the state a live settings screen needs (theme, toggles, subscription) so the preview
/// composes the real rows end-to-end.
private struct SettingsScreenPreview: View {
    @State private var themeManager = ThemeManager()
    @State private var subscriptions = SubscriptionManager(productIDs: ["pro.yearly"])
    @State private var notificationsEnabled = true
    @State private var analyticsEnabled = false

    var body: some View {
        NavigationStack {
            SettingsScreen {
                SettingsSection(header: "Appearance") {
                    SettingsRow(title: "Theme") {
                        ThemePickerRow(manager: themeManager)
                    }
                }

                SettingsSection(header: "Preferences") {
                    SettingsRow(title: "Notifications") {
                        ToggleRow("Notifications", systemImage: "bell", isOn: $notificationsEnabled)
                    }
                    SettingsRow(title: "Analytics") {
                        ToggleRow("Share analytics", systemImage: "chart.bar", isOn: $analyticsEnabled)
                    }
                    SettingsRow(title: "Advanced") {
                        NavigationLinkRow("Advanced", systemImage: "gearshape.2") {
                            Text("Advanced settings")
                        }
                    }
                }

                SettingsSection(header: "Subscription") {
                    SettingsRow(title: "Manage") {
                        ManageSubscriptionRow(manager: subscriptions)
                    }
                }

                SettingsSection(header: "About", footer: "Thanks for using the app.") {
                    SettingsRow(title: "Privacy") {
                        LinkRow("Privacy Policy", systemImage: "hand.raised",
                                url: URL(string: "https://example.com/privacy")!)
                    }
                    SettingsRow(title: "Terms") {
                        LinkRow("Terms of Service", systemImage: "doc.text",
                                url: URL(string: "https://example.com/terms")!)
                    }
                    SettingsRow(title: "Contact") {
                        LinkRow("Contact Support", systemImage: "envelope",
                                email: "support@example.com", subject: "Need help")
                    }
                    SettingsRow(title: "Sign Out") {
                        ButtonRow("Sign Out", systemImage: "rectangle.portrait.and.arrow.right",
                                  role: .destructive) {}
                    }
                }

                SettingsSection {
                    SettingsRow(title: "App Info") {
                        AppInfoFooter(appName: "Kits Demo")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .themed(themeManager)
    }
}
