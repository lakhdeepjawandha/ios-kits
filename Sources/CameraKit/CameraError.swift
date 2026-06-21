import Foundation

/// Errors surfaced by the camera capture pipeline.
public enum CameraError: Error, Equatable {
    /// Camera access is not authorized. Carries the current authorization for context.
    case notAuthorized(CameraAuthorization)
    /// No usable capture device exists (e.g. running in the Simulator).
    case cameraUnavailable
    /// The capture device could not be added as a session input.
    case cannotAddInput
    /// A capture output could not be added to the session.
    case cannotAddOutput
    /// Session configuration failed. Carries a message.
    case configurationFailed(String)
    /// A photo or video capture failed. Carries a message.
    case captureFailed(String)
    /// The captured photo data could not be decoded into an image.
    case invalidPhotoData
}

extension CameraError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notAuthorized(auth):     return "Camera not authorized (\(auth))."
        case .cameraUnavailable:           return "No camera is available on this device."
        case .cannotAddInput:              return "The camera input could not be added to the session."
        case .cannotAddOutput:             return "A capture output could not be added to the session."
        case let .configurationFailed(m):  return "Camera configuration failed: \(m)"
        case let .captureFailed(m):        return "Capture failed: \(m)"
        case .invalidPhotoData:            return "The captured photo could not be decoded."
        }
    }
}
