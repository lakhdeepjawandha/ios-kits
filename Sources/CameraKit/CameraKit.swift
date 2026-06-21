import RenderKit

/// AVFoundation capture session + Metal preview pipeline.
///
/// ## Topics
/// ### Permissions & state
/// - ``CameraAuthorization``
/// - ``CameraSessionState``
/// - ``CameraStateMachine``
/// ### Configuration
/// - ``CameraConfiguration``
/// - ``CameraPosition``
/// - ``CameraQuality``
/// - ``CaptureGeometry``
/// ### Capture & UI
/// - ``CaptureController``
/// - ``CameraView``
/// - ``CameraError``
///
/// The permission state machine and configuration math are pure and unit-tested; the AVFoundation
/// capture controller and SwiftUI preview are iOS-only (guarded by `#if canImport(UIKit)`) and
/// degrade gracefully where no camera exists.
public enum CameraKit {
    /// Short description of the module.
    public static let info = "AVFoundation capture + Metal preview."
}
