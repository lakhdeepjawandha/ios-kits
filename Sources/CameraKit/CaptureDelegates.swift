#if canImport(UIKit)
import AVFoundation
import CoreMedia

/// Forwards sample-buffer frames from `AVCaptureVideoDataOutput` to a callback on the capture queue.
/// Kept separate from the `@MainActor` controller so the background delegate callback has no
/// actor-isolation friction.
final class FrameForwarder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on the video data output's queue for each frame.
    var onFrame: ((CVPixelBuffer) -> Void)?

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}

/// One-shot photo capture delegate that bridges `AVCapturePhotoOutput` to a completion handler.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            completion(.failure(CameraError.captureFailed(error.localizedDescription)))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(CameraError.invalidPhotoData))
        }
    }
}

/// Movie-file recording delegate bridging `AVCaptureMovieFileOutput` to a completion handler.
final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    /// Called when recording finishes (successfully or with an error).
    var onFinish: ((Result<URL, Error>) -> Void)?

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error {
            onFinish?(.failure(CameraError.captureFailed(error.localizedDescription)))
        } else {
            onFinish?(.success(outputFileURL))
        }
    }
}
#endif
