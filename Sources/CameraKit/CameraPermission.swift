import AVFoundation

/// The app's camera authorization, mirroring `AVAuthorizationStatus` in a small, testable form.
public enum CameraAuthorization: Equatable, Sendable {
    /// The user has not yet been asked.
    case notDetermined
    /// The user granted camera access.
    case authorized
    /// The user explicitly denied camera access.
    case denied
    /// Access is restricted (e.g. parental controls / MDM); the user cannot grant it.
    case restricted

    /// Map from an `AVAuthorizationStatus`.
    public init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:    self = .authorized
        case .denied:        self = .denied
        case .restricted:    self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default:    self = .denied
        }
    }

    /// Whether camera access is granted.
    public var isAuthorized: Bool { self == .authorized }

    /// Whether the app may still show the system permission prompt (only when not yet determined).
    public var canRequest: Bool { self == .notDetermined }

    /// Whether the user must change permission in Settings (a terminal denial the app can't prompt).
    public var requiresSettings: Bool { self == .denied || self == .restricted }
}

/// The overall readiness of the capture pipeline, combining authorization, hardware availability,
/// and run state. This is a **pure state machine** so it can be unit-tested without any camera.
public enum CameraSessionState: Equatable, Sendable {
    /// Initial state, before anything has been evaluated.
    case idle
    /// Authorization hasn't been decided; the app should request access.
    case needsAuthorization
    /// Access is denied/restricted; the app should guide the user to Settings.
    case denied
    /// Authorized, but no usable camera exists (e.g. the Simulator).
    case unavailable
    /// Authorized with hardware present; configured but not running.
    case ready
    /// The session is actively running.
    case running
    /// Setup or capture failed. Carries a message.
    case failed(String)

    /// Whether the preview can show live frames in this state.
    public var isRunning: Bool { self == .running }
}

/// A pure reducer that derives ``CameraSessionState`` from authorization, hardware availability, and
/// lifecycle events. Keeping the transitions here (rather than scattered through the AVFoundation
/// controller) makes the behaviour exhaustively testable.
public struct CameraStateMachine: Equatable, Sendable {
    /// The current derived state.
    public private(set) var state: CameraSessionState

    /// Create a machine, optionally starting in a specific state. Default ``CameraSessionState/idle``.
    public init(state: CameraSessionState = .idle) {
        self.state = state
    }

    /// Recompute the state from the latest authorization and whether a camera is present.
    ///
    /// Preserves ``CameraSessionState/running`` when still authorized with hardware (so a routine
    /// re-evaluation doesn't appear to stop the session); otherwise resolves to `ready`,
    /// `needsAuthorization`, `denied`, or `unavailable`.
    ///
    /// - Parameters:
    ///   - authorization: The current authorization.
    ///   - hasCamera: Whether a usable capture device exists.
    public mutating func update(authorization: CameraAuthorization, hasCamera: Bool) {
        switch authorization {
        case .notDetermined:
            state = .needsAuthorization
        case .denied, .restricted:
            state = .denied
        case .authorized:
            guard hasCamera else { state = .unavailable; return }
            state = (state == .running) ? .running : .ready
        }
    }

    /// Mark the session as running. Ignored unless currently `ready` or already `running`.
    public mutating func didStartRunning() {
        if state == .ready || state == .running { state = .running }
    }

    /// Mark the session as stopped (back to `ready`). Ignored unless currently `running`.
    public mutating func didStopRunning() {
        if state == .running { state = .ready }
    }

    /// Move to a failed state with a message.
    public mutating func didFail(_ message: String) {
        state = .failed(message)
    }
}
