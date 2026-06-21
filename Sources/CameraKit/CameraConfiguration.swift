import AVFoundation
import CoreGraphics

/// Which physical camera to use.
public enum CameraPosition: Equatable, Sendable {
    case front
    case back

    /// The matching `AVCaptureDevice.Position`.
    public var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back:  return .back
        }
    }

    /// The opposite camera (for a flip button).
    public var toggled: CameraPosition {
        self == .front ? .back : .front
    }
}

/// Capture quality, mapped to an `AVCaptureSession.Preset`.
public enum CameraQuality: Equatable, Sendable {
    /// Best still-photo quality.
    case photo
    /// High-quality video.
    case high
    /// Balanced quality (smaller buffers; good for live ML/processing).
    case medium
    /// Low quality (lowest bandwidth).
    case low

    /// The matching `AVCaptureSession.Preset`.
    public var preset: AVCaptureSession.Preset {
        switch self {
        case .photo:  return .photo
        case .high:   return .high
        case .medium: return .medium
        case .low:    return .low
        }
    }
}

/// Declarative capture configuration applied when the session is set up.
public struct CameraConfiguration: Equatable, Sendable {
    /// Starting camera.
    public var position: CameraPosition
    /// Capture quality preset.
    public var quality: CameraQuality
    /// Whether to add an audio input (needed for video with sound).
    public var enablesAudio: Bool
    /// Whether to add a still-photo output.
    public var enablesPhoto: Bool
    /// Whether to add a movie-file output.
    public var enablesVideo: Bool
    /// Whether to emit live frames as an `AsyncStream<CVPixelBuffer>`.
    public var enablesFrameStream: Bool

    /// Create a configuration.
    ///
    /// - Parameters:
    ///   - position: Starting camera. Default `.back`.
    ///   - quality: Preset. Default `.high`.
    ///   - enablesAudio: Add audio input. Default `false`.
    ///   - enablesPhoto: Add photo output. Default `true`.
    ///   - enablesVideo: Add movie output. Default `false`.
    ///   - enablesFrameStream: Emit a live frame stream. Default `true`.
    public init(position: CameraPosition = .back,
                quality: CameraQuality = .high,
                enablesAudio: Bool = false,
                enablesPhoto: Bool = true,
                enablesVideo: Bool = false,
                enablesFrameStream: Bool = true) {
        self.position = position
        self.quality = quality
        self.enablesAudio = enablesAudio
        self.enablesPhoto = enablesPhoto
        self.enablesVideo = enablesVideo
        self.enablesFrameStream = enablesFrameStream
    }

    /// A photo-oriented preset (photo quality, no video/audio).
    public static let photo = CameraConfiguration(quality: .photo, enablesVideo: false)
    /// A video-oriented preset (high quality, audio + movie output).
    public static let video = CameraConfiguration(quality: .high, enablesAudio: true,
                                                  enablesPhoto: false, enablesVideo: true)
}

/// Pure geometry helpers for translating UI gestures into camera parameters.
public enum CaptureGeometry {
    /// Convert a tap point in view coordinates to a normalized device point of interest (`0...1`),
    /// clamped to the valid range.
    ///
    /// Focus/exposure points of interest are expressed in a normalized `0...1` space. This performs
    /// the straightforward fit used for a full-bleed portrait preview; it clamps out-of-bounds taps
    /// and returns the centre `(0.5, 0.5)` for a degenerate (zero-area) view.
    ///
    /// - Parameters:
    ///   - viewPoint: The tap location in view points.
    ///   - viewSize: The view's size in points.
    /// - Returns: A normalized, clamped point of interest.
    public static func normalizedPoint(viewPoint: CGPoint, viewSize: CGSize) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let x = (viewPoint.x / viewSize.width).clampedUnit()
        let y = (viewPoint.y / viewSize.height).clampedUnit()
        return CGPoint(x: x, y: y)
    }
}

private extension CGFloat {
    func clampedUnit() -> CGFloat { Swift.min(1, Swift.max(0, self)) }
}
