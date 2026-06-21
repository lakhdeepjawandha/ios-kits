import Vision
import CoreGraphics
import CoreVideo
import ImageIO

/// On-device subject cutout using `VNGeneratePersonSegmentationRequest`. Produces a grayscale mask
/// where brighter pixels are more likely to belong to a person — the basis for a background remover.
///
/// Everything runs on-device. Use ``generateMask(for:orientation:)`` for the raw mask pixel buffer,
/// or ``generateMaskImage(for:orientation:)`` for a `CGImage` you can composite.
public struct Segmenter {

    /// Mask quality / cost trade-off.
    public enum Quality: Sendable {
        /// Lowest latency (good for live video).
        case fast
        /// Balanced quality and cost.
        case balanced
        /// Highest quality (best for stills).
        case accurate

        var level: VNGeneratePersonSegmentationRequest.QualityLevel {
            switch self {
            case .fast:     return .fast
            case .balanced: return .balanced
            case .accurate: return .accurate
            }
        }
    }

    /// The mask quality level.
    public var quality: Quality

    /// Create a segmenter.
    ///
    /// - Parameter quality: Mask quality. Default `.balanced`.
    public init(quality: Quality = .balanced) {
        self.quality = quality
    }

    /// Generate a person-segmentation mask for an image.
    ///
    /// - Parameters:
    ///   - cgImage: The source image.
    ///   - orientation: The image's orientation. Default `.up`.
    /// - Returns: A single-channel mask `CVPixelBuffer` (`kCVPixelFormatType_OneComponent8`).
    /// - Throws: ``VisionScanError/segmentationFailed`` if no mask is produced, or any handler error.
    public func generateMask(for cgImage: CGImage,
                             orientation: CGImagePropertyOrientation = .up) throws -> CVPixelBuffer {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality.level
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])

        guard let mask = request.results?.first?.pixelBuffer else {
            throw VisionScanError.segmentationFailed
        }
        return mask
    }

    /// Generate the segmentation mask as a `CGImage` (grayscale), convenient for compositing.
    ///
    /// - Parameters:
    ///   - cgImage: The source image.
    ///   - orientation: The image's orientation. Default `.up`.
    /// - Returns: A grayscale mask image.
    /// - Throws: ``VisionScanError`` or any handler error.
    public func generateMaskImage(for cgImage: CGImage,
                                  orientation: CGImagePropertyOrientation = .up) throws -> CGImage {
        let mask = try generateMask(for: cgImage, orientation: orientation)
        guard let image = Self.makeGrayCGImage(from: mask) else {
            throw VisionScanError.segmentationFailed
        }
        return image
    }

    /// Convert a one-component8 mask buffer into a grayscale `CGImage`.
    static func makeGrayCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: base,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        return context.makeImage()
    }
}
