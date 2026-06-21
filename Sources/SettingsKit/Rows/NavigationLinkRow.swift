import SwiftUI

/// A settings row that pushes a destination view when tapped, via `NavigationLink`.
///
/// Place inside a `NavigationStack` (as ``SettingsScreen`` is typically presented):
///
/// ```swift
/// NavigationLinkRow("Acknowledgements", systemImage: "doc.text") {
///     AcknowledgementsView()
/// }
/// ```
public struct NavigationLinkRow<Destination: View>: View {
    private let title: String
    private let systemImage: String?
    private let destination: Destination

    /// Creates a navigation-link row.
    /// - Parameters:
    ///   - title: The row's label.
    ///   - systemImage: Optional SF Symbol shown before the label.
    ///   - destination: The view pushed when the row is tapped.
    public init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.destination = destination()
    }

    public var body: some View {
        NavigationLink {
            destination
        } label: {
            settingsRowLabel(title, systemImage: systemImage)
        }
    }
}

#Preview("Navigation Link Row") {
    NavigationStack {
        Form {
            NavigationLinkRow("Acknowledgements", systemImage: "doc.text") {
                Text("Licenses")
            }
            NavigationLinkRow("Advanced") {
                Text("Advanced settings")
            }
        }
    }
}
