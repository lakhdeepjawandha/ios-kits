#if canImport(UIKit)
import SwiftUI

/// A SwiftUI camera screen: a full-bleed Metal preview with a custom HUD overlaid on top.
///
/// `CameraView` owns the lifecycle — it asks permission and starts the session on appear — and
/// renders an appropriate placeholder for the unauthorized / unavailable states. Provide your
/// controls (shutter button, flip, torch, readouts) via the `hud` builder; they're laid over the
/// preview in a `ZStack`.
///
/// ```swift
/// CameraView(controller: controller) {
///     VStack {
///         Spacer()
///         HStack {
///             Button("Flip") { Task { await controller.switchCamera() } }
///             Button("Shutter") { Task { lastPhoto = try? await controller.capturePhoto() } }
///         }
///     }
/// }
/// ```
public struct CameraView<HUD: View>: View {
    private let controller: CaptureController
    @ViewBuilder private let hud: () -> HUD

    /// Create a camera view.
    ///
    /// - Parameters:
    ///   - controller: The capture controller to present and drive.
    ///   - hud: Overlay content drawn above the preview.
    public init(controller: CaptureController, @ViewBuilder hud: @escaping () -> HUD) {
        self.controller = controller
        self.hud = hud
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            hud()
        }
        .task {
            await controller.prepare()
            controller.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .ready, .running:
            MetalCameraPreview(controller: controller)
                .ignoresSafeArea()
        case .denied:
            placeholder(systemImage: "lock.slash",
                        title: "Camera Access Needed",
                        message: "Enable camera access in Settings to continue.")
        case .unavailable:
            placeholder(systemImage: "camera.metering.unknown",
                        title: "Camera Unavailable",
                        message: "This device has no usable camera (e.g. the Simulator).")
        case .failed(let message):
            placeholder(systemImage: "exclamationmark.triangle",
                        title: "Camera Error",
                        message: message)
        case .idle, .needsAuthorization:
            ProgressView().tint(.white)
        }
    }

    private func placeholder(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding()
    }
}

public extension CameraView where HUD == EmptyView {
    /// Create a camera view with no HUD overlay.
    init(controller: CaptureController) {
        self.init(controller: controller) { EmptyView() }
    }
}

#Preview {
    // In the Simulator this shows the graceful "Camera Unavailable" state.
    CameraView(controller: CaptureController(configuration: .photo)) {
        VStack {
            Spacer()
            Text("HUD overlay")
                .padding()
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 40)
        }
    }
}
#endif
