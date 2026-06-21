import SwiftUI

// MARK: - ShareLink convenience

/// A pre-styled share button backed by SwiftUI's `ShareLink`.
///
/// Use it when you just need a standard "Share" affordance for a piece of text or a URL
/// without configuring `ShareLink` each time:
///
/// ```swift
/// ShareButton(url: article.url)
/// ShareButton(text: "Check out my portfolio")
/// ```
public struct ShareButton: View {
    private enum Content {
        case text(String)
        case url(URL)
    }

    private let content: Content
    private let title: String

    /// Creates a share button for a plain-text item.
    /// - Parameters:
    ///   - text: The text to share.
    ///   - title: The button label. Defaults to `"Share"`.
    public init(text: String, title: String = "Share") {
        self.content = .text(text)
        self.title = title
    }

    /// Creates a share button for a URL.
    /// - Parameters:
    ///   - url: The URL to share.
    ///   - title: The button label. Defaults to `"Share"`.
    public init(url: URL, title: String = "Share") {
        self.content = .url(url)
        self.title = title
    }

    public var body: some View {
        switch content {
        case .text(let text):
            ShareLink(item: text) { label }
        case .url(let url):
            ShareLink(item: url) { label }
        }
    }

    private var label: some View {
        Label(title, systemImage: "square.and.arrow.up")
    }
}

// MARK: - UIActivityViewController wrapper

#if canImport(UIKit)
import UIKit

/// A SwiftUI wrapper around `UIActivityViewController` for sharing arbitrary items.
///
/// Unlike ``ShareButton`` / `ShareLink`, this presents the full system share sheet and accepts
/// heterogeneous activity items — text, `URL`, `UIImage`, or a file `URL`:
///
/// ```swift
/// .sheet(isPresented: $isSharing) {
///     ShareSheet(activityItems: ["My report", reportFileURL])
/// }
/// ```
///
/// For the common case prefer the ``SwiftUICore/View/shareSheet(isPresented:activityItems:applicationActivities:onComplete:)``
/// modifier.
public struct ShareSheet: UIViewControllerRepresentable {
    /// The items to share. Supported element types include `String`, `URL`, and `UIImage`.
    public let activityItems: [Any]
    /// Optional custom application activities to offer alongside the system ones.
    public let applicationActivities: [UIActivity]?
    /// Invoked when the sheet is dismissed; the flag is `true` if the user completed an action.
    public let onComplete: ((Bool) -> Void)?

    /// Creates a share sheet.
    /// - Parameters:
    ///   - activityItems: The items to share (text, `URL`, `UIImage`, file `URL`, …).
    ///   - applicationActivities: Optional custom activities. Defaults to `nil`.
    ///   - onComplete: Optional completion called with whether the user finished an action.
    public init(
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        self.onComplete = onComplete
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

public extension View {
    /// Presents a system share sheet (``ShareSheet``) for the given items when `isPresented` is `true`.
    /// - Parameters:
    ///   - isPresented: Binding controlling presentation.
    ///   - activityItems: The items to share (text, `URL`, `UIImage`, file `URL`, …).
    ///   - applicationActivities: Optional custom activities. Defaults to `nil`.
    ///   - onComplete: Optional completion called with whether the user finished an action.
    func shareSheet(
        isPresented: Binding<Bool>,
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        onComplete: ((Bool) -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            ShareSheet(
                activityItems: activityItems,
                applicationActivities: applicationActivities,
                onComplete: onComplete
            )
        }
    }
}
#endif
