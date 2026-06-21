#if canImport(UIKit) && canImport(VisionKit)
import SwiftUI
import VisionKit
import UIKit

/// A SwiftUI wrapper around VisionKit's `VNDocumentCameraViewController` — the system document
/// scanner with automatic edge detection, multi-page capture, and perspective correction.
///
/// Present it (e.g. in a `.sheet`) and receive the scanned pages as `UIImage`s.
///
/// ```swift
/// .sheet(isPresented: $scanning) {
///     DocumentCameraView { result in
///         scanning = false
///         if case let .success(pages) = result { self.pages = pages }
///     }
/// }
/// ```
///
/// - Note: iOS only. The device must support document scanning
///   (`VNDocumentCameraViewController.isSupported`).
public struct DocumentCameraView: UIViewControllerRepresentable {
    /// The outcome of a scanning session.
    public enum ScanResult {
        /// One or more scanned pages, in order.
        case success([UIImage])
        /// The user cancelled.
        case cancelled
        /// Scanning failed. Carries the error.
        case failed(Error)
    }

    private let completion: (ScanResult) -> Void

    /// Create a document camera view.
    ///
    /// - Parameter completion: Called once when scanning finishes, is cancelled, or fails.
    public init(completion: @escaping (ScanResult) -> Void) {
        self.completion = completion
    }

    /// Whether the current device supports the document scanner.
    public static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    public func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    /// Bridges `VNDocumentCameraViewControllerDelegate` callbacks to the completion handler.
    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let completion: (ScanResult) -> Void

        init(completion: @escaping (ScanResult) -> Void) {
            self.completion = completion
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            completion(.success(pages))
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completion(.cancelled)
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFailWithError error: Error) {
            completion(.failed(error))
        }
    }
}
#endif
