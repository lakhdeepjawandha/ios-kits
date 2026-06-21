import SwiftUI

/// A settings row that opens an external URL — a web link (privacy / terms) or a `mailto:`
/// address (contact / support).
///
/// ```swift
/// LinkRow("Privacy Policy", systemImage: "hand.raised", url: privacyURL)
/// LinkRow("Contact Support", systemImage: "envelope", email: "support@example.com", subject: "Help")
/// ```
public struct LinkRow: View {
    private let title: String
    private let systemImage: String?
    private let url: URL

    /// Creates a link row for a web (or any) URL.
    /// - Parameters:
    ///   - title: The row's label.
    ///   - systemImage: Optional SF Symbol shown before the label.
    ///   - url: The URL to open when tapped.
    public init(_ title: String, systemImage: String? = nil, url: URL) {
        self.title = title
        self.systemImage = systemImage
        self.url = url
    }

    /// Creates a link row that opens a pre-filled email via a `mailto:` URL.
    /// - Parameters:
    ///   - title: The row's label.
    ///   - systemImage: Optional SF Symbol shown before the label.
    ///   - email: The recipient address.
    ///   - subject: Optional pre-filled subject line.
    ///   - body: Optional pre-filled message body.
    public init(
        _ title: String,
        systemImage: String? = nil,
        email: String,
        subject: String? = nil,
        body: String? = nil
    ) {
        let mailto = Self.mailtoURL(email: email, subject: subject, body: body)
        self.init(title, systemImage: systemImage, url: mailto ?? URL(string: "mailto:")!)
    }

    public var body: some View {
        Link(destination: url) {
            settingsRowLabel(title, systemImage: systemImage)
        }
    }

    /// Builds a `mailto:` URL with optional subject and body, percent-encoding the query.
    ///
    /// Pure and standalone so the URL construction can be unit-tested.
    /// - Parameters:
    ///   - email: The recipient address.
    ///   - subject: Optional subject line.
    ///   - body: Optional message body.
    /// - Returns: A `mailto:` URL, or `nil` if components could not form a valid URL.
    public static func mailtoURL(email: String, subject: String? = nil, body: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        var items: [URLQueryItem] = []
        if let subject { items.append(URLQueryItem(name: "subject", value: subject)) }
        if let body { items.append(URLQueryItem(name: "body", value: body)) }
        if !items.isEmpty { components.queryItems = items }
        return components.url
    }
}

#Preview("Link Row") {
    Form {
        LinkRow("Privacy Policy", systemImage: "hand.raised",
                url: URL(string: "https://example.com/privacy")!)
        LinkRow("Contact Support", systemImage: "envelope",
                email: "support@example.com", subject: "Need help")
    }
}
