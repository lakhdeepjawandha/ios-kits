import Vision
import CoreImage
import CoreGraphics
import ImageIO

/// Document edge detection and perspective correction for a single image, on-device.
///
/// Use ``detectRectangle(in:)`` to find the document quad, ``correctedImage(from:)`` to deskew and
/// crop it to a flat rectangle, or the VisionKit-based scanner UI (``DocumentCameraView``, iOS only)
/// to capture pages with the system scanner.
public struct DocumentScanner {
    /// Minimum confidence for an accepted rectangle. Default `0.6`.
    public var minimumConfidence: VNConfidence
    /// Minimum aspect ratio (w:h) of detected rectangles. Default `0.3`.
    public var minimumAspectRatio: Float
    /// Minimum size as a fraction of the image. Default `0.2`.
    public var minimumSize: Float

    private let ciContext: CIContext

    /// Create a document scanner.
    ///
    /// - Parameters:
    ///   - minimumConfidence: Minimum rectangle confidence. Default `0.6`.
    ///   - minimumAspectRatio: Minimum aspect ratio. Default `0.3`.
    ///   - minimumSize: Minimum relative size. Default `0.2`.
    ///   - ciContext: Core Image context for rendering. Default a fresh `CIContext`.
    public init(minimumConfidence: VNConfidence = 0.6,
                minimumAspectRatio: Float = 0.3,
                minimumSize: Float = 0.2,
                ciContext: CIContext = CIContext()) {
        self.minimumConfidence = minimumConfidence
        self.minimumAspectRatio = minimumAspectRatio
        self.minimumSize = minimumSize
        self.ciContext = ciContext
    }

    /// Detect the most prominent rectangle (document edges) in an image.
    ///
    /// - Parameters:
    ///   - cgImage: The image to analyze.
    ///   - orientation: The image's orientation. Default `.up`.
    /// - Returns: The highest-confidence rectangle, or `nil` if none meets the thresholds.
    /// - Throws: Any Vision handler error.
    public func detectRectangle(in cgImage: CGImage,
                                orientation: CGImagePropertyOrientation = .up) throws -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = minimumConfidence
        request.minimumAspectRatio = minimumAspectRatio
        request.minimumSize = minimumSize
        request.maximumObservations = 1

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])
        return request.results?.first
    }

    /// Deskew and crop an image to its detected document rectangle.
    ///
    /// - Parameters:
    ///   - cgImage: The source image.
    ///   - orientation: The image's orientation. Default `.up`.
    /// - Returns: A perspective-corrected `CGImage`.
    /// - Throws: ``VisionScanError/noDocumentDetected`` if no rectangle is found, or
    ///   ``VisionScanError/imageProcessingFailed`` if rendering fails.
    public func correctedImage(from cgImage: CGImage,
                               orientation: CGImagePropertyOrientation = .up) throws -> CGImage {
        guard let rectangle = try detectRectangle(in: cgImage, orientation: orientation) else {
            throw VisionScanError.noDocumentDetected
        }
        return try correctPerspective(of: cgImage, to: rectangle)
    }

    /// Apply perspective correction to an image given a detected rectangle (normalized corners).
    ///
    /// - Parameters:
    ///   - cgImage: The source image.
    ///   - rectangle: The detected rectangle (corners in normalized, bottom-left-origin space).
    /// - Returns: The corrected, cropped `CGImage`.
    /// - Throws: ``VisionScanError/imageProcessingFailed`` if rendering fails.
    public func correctPerspective(of cgImage: CGImage,
                                   to rectangle: VNRectangleObservation) throws -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        func denormalize(_ point: CGPoint) -> CIVector {
            CIVector(x: point.x * extent.width, y: point.y * extent.height)
        }

        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(denormalize(rectangle.topLeft), forKey: "inputTopLeft")
        filter.setValue(denormalize(rectangle.topRight), forKey: "inputTopRight")
        filter.setValue(denormalize(rectangle.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(denormalize(rectangle.bottomRight), forKey: "inputBottomRight")

        guard let output = filter.outputImage,
              let result = ciContext.createCGImage(output, from: output.extent) else {
            throw VisionScanError.imageProcessingFailed
        }
        return result
    }
}
