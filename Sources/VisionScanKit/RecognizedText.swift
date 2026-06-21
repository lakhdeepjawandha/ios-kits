import CoreGraphics

/// A single piece of recognized text with its location and confidence.
///
/// `boundingBox` is in Vision's normalized image coordinates: `(0,0)` is the **bottom-left** and
/// `(1,1)` the top-right, relative to the input image.
public struct RecognizedText: Equatable, Sendable {
    /// The recognized string (top candidate).
    public let string: String
    /// Recognition confidence in `0...1`.
    public let confidence: Float
    /// Normalized bounding box (bottom-left origin).
    public let boundingBox: CGRect

    /// Create a recognized-text value.
    public init(string: String, confidence: Float, boundingBox: CGRect) {
        self.string = string
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}
