#if canImport(UIKit)
import AVFoundation
import Observation
import CoreGraphics
import ImageIO
import Foundation

/// Drives an `AVCaptureSession`: permissions, configuration, start/stop, camera switching, torch,
/// focus/exposure, a live frame stream, and photo/video capture.
///
/// `@Observable` so SwiftUI views react to ``authorization``, ``state``, ``isTorchOn``, and
/// ``isRecording``. All session mutation runs on a dedicated serial queue; published state is
/// updated on the main actor. It degrades gracefully where no camera exists (the Simulator):
/// ``state`` becomes ``CameraSessionState/unavailable`` instead of crashing.
///
/// ```swift
/// let controller = CaptureController(configuration: .photo)
/// await controller.prepare()      // asks permission + configures
/// controller.start()
/// for await pixelBuffer in controller.frames() { /* process */ }
/// let image = try await controller.capturePhoto()
/// ```
@MainActor
@Observable
public final class CaptureController {

    /// Current camera authorization.
    public private(set) var authorization: CameraAuthorization
    /// Current pipeline state (derived by ``CameraStateMachine``).
    public private(set) var state: CameraSessionState = .idle
    /// Active camera position.
    public private(set) var position: CameraPosition
    /// Whether the torch is currently on.
    public private(set) var isTorchOn: Bool = false
    /// Whether a video recording is in progress.
    public private(set) var isRecording: Bool = false
    /// The capture configuration (mutated as the camera switches).
    public private(set) var configuration: CameraConfiguration

    /// The underlying session (exposed for advanced integration / preview layers).
    @ObservationIgnored nonisolated(unsafe) public let session = AVCaptureSession()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "CameraKit.session")
    @ObservationIgnored private let frameQueue = DispatchQueue(label: "CameraKit.frames")
    @ObservationIgnored private var stateMachine = CameraStateMachine()

    @ObservationIgnored nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    @ObservationIgnored nonisolated(unsafe) private var audioInput: AVCaptureDeviceInput?
    @ObservationIgnored nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()

    @ObservationIgnored private let frameForwarder = FrameForwarder()
    @ObservationIgnored private let recordingDelegate = RecordingDelegate()
    @ObservationIgnored nonisolated(unsafe) private var photoDelegate: PhotoCaptureDelegate?
    @ObservationIgnored nonisolated(unsafe) private var frameContinuation: AsyncStream<CVPixelBuffer>.Continuation?

    /// Create a controller with a configuration. Reads the current authorization but does not yet
    /// prompt — call ``prepare()`` to request access and configure.
    public init(configuration: CameraConfiguration = CameraConfiguration()) {
        self.configuration = configuration
        self.position = configuration.position
        self.authorization = CameraAuthorization(AVCaptureDevice.authorizationStatus(for: .video))
    }

    private var currentDevice: AVCaptureDevice? { videoInput?.device }

    // MARK: - Availability

    /// Whether a wide-angle camera exists at the given position (false in the Simulator).
    public static func hasCamera(at position: CameraPosition) -> Bool {
        device(at: position) != nil
    }

    static func device(at position: CameraPosition) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avPosition)
    }

    // MARK: - Permission + configuration

    /// Request authorization if needed, then configure the session if possible.
    ///
    /// Updates ``authorization`` and ``state``. Safe to call repeatedly; it only configures once
    /// the user is authorized and a camera is present.
    public func prepare() async {
        if authorization.canRequest {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        } else {
            authorization = CameraAuthorization(AVCaptureDevice.authorizationStatus(for: .video))
        }

        let hasCam = Self.hasCamera(at: position)
        stateMachine.update(authorization: authorization, hasCamera: hasCam)
        state = stateMachine.state

        guard authorization.isAuthorized, hasCam else { return }
        await configureSession()
    }

    private func configureSession() async {
        let config = configuration
        let pos = position
        let error: CameraError? = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                session.beginConfiguration()
                session.sessionPreset = config.quality.preset

                // Video input.
                guard let device = Self.device(at: pos),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    session.commitConfiguration()
                    continuation.resume(returning: .cameraUnavailable); return
                }
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    continuation.resume(returning: .cannotAddInput); return
                }
                session.addInput(input)
                videoInput = input

                // Audio input (optional).
                if config.enablesAudio,
                   let mic = AVCaptureDevice.default(for: .audio),
                   let micInput = try? AVCaptureDeviceInput(device: mic),
                   session.canAddInput(micInput) {
                    session.addInput(micInput)
                    audioInput = micInput
                }

                // Frame stream output.
                if config.enablesFrameStream {
                    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.setSampleBufferDelegate(frameForwarder, queue: frameQueue)
                    if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
                }

                // Photo output.
                if config.enablesPhoto, session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                }

                // Movie output.
                if config.enablesVideo, session.canAddOutput(movieOutput) {
                    session.addOutput(movieOutput)
                }

                session.commitConfiguration()
                continuation.resume(returning: nil)
            }
        }

        if let error {
            stateMachine.didFail(error.localizedDescription)
            state = stateMachine.state
            return
        }

        frameForwarder.onFrame = { [weak self] pixelBuffer in
            self?.frameContinuation?.yield(pixelBuffer)
        }
    }

    // MARK: - Run control

    /// Start the capture session.
    public func start() {
        guard state == .ready || state == .running else { return }
        let captureSession = session
        sessionQueue.async {
            if !captureSession.isRunning { captureSession.startRunning() }
        }
        stateMachine.didStartRunning()
        state = stateMachine.state
    }

    /// Stop the capture session.
    public func stop() {
        let captureSession = session
        sessionQueue.async {
            if captureSession.isRunning { captureSession.stopRunning() }
        }
        stateMachine.didStopRunning()
        state = stateMachine.state
    }

    // MARK: - Live frames

    /// A live stream of camera frames as `CVPixelBuffer`s (BGRA). The most recent call's stream
    /// receives frames; terminating the stream stops delivery.
    public func frames() -> AsyncStream<CVPixelBuffer> {
        AsyncStream { continuation in
            self.frameContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.frameContinuation = nil }
            }
        }
    }

    // MARK: - Camera switching

    /// Switch between the front and back cameras, reconfiguring the session input.
    public func switchCamera() async {
        let newPosition = position.toggled
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                session.beginConfiguration()
                if let current = videoInput { session.removeInput(current) }
                if let device = Self.device(at: newPosition),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    videoInput = input
                }
                session.commitConfiguration()
                continuation.resume()
            }
        }
        position = newPosition
        configuration.position = newPosition
        isTorchOn = false
    }

    // MARK: - Torch

    /// Turn the torch on or off (no-op if the device has no torch).
    public func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice, device.hasTorch,
                  (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            Task { @MainActor in self?.isTorchOn = on }
        }
    }

    // MARK: - Focus / exposure

    /// Set focus and exposure to a tap point in view coordinates.
    ///
    /// - Parameters:
    ///   - viewPoint: The tapped location in view points.
    ///   - viewSize: The preview view's size in points.
    public func focus(at viewPoint: CGPoint, viewSize: CGSize) {
        let point = CaptureGeometry.normalizedPoint(viewPoint: viewPoint, viewSize: viewSize)
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice,
                  (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: - Photo capture

    /// Capture a still photo and return its encoded data (HEIC/JPEG per device default).
    public func capturePhotoData() async throws -> Data {
        guard configuration.enablesPhoto else {
            throw CameraError.captureFailed("Photo output is disabled in the configuration.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                continuation.resume(with: result)
                self?.photoDelegate = nil
            }
            self.photoDelegate = delegate
            let settings = AVCapturePhotoSettings()
            sessionQueue.async { [photoOutput] in
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    /// Capture a still photo and decode it to a `CGImage`.
    public func capturePhoto() async throws -> CGImage {
        let data = try await capturePhotoData()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CameraError.invalidPhotoData
        }
        return image
    }

    // MARK: - Video capture

    /// Start recording video to a file.
    ///
    /// - Parameter url: Destination URL. Defaults to a unique `.mov` in the temporary directory.
    /// - Returns: The URL being written to.
    @discardableResult
    public func startRecording(to url: URL? = nil) throws -> URL {
        guard configuration.enablesVideo else {
            throw CameraError.captureFailed("Movie output is disabled in the configuration.")
        }
        let destination = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        sessionQueue.async { [movieOutput, recordingDelegate] in
            movieOutput.startRecording(to: destination, recordingDelegate: recordingDelegate)
        }
        isRecording = true
        return destination
    }

    /// Stop recording and return the finished file URL.
    public func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            recordingDelegate.onFinish = { [weak self] result in
                continuation.resume(with: result)
                Task { @MainActor in self?.isRecording = false }
            }
            sessionQueue.async { [movieOutput] in
                movieOutput.stopRecording()
            }
        }
    }
}
#endif
