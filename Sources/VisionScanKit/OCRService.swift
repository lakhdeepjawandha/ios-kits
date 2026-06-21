import Vision
import CoreGraphics
import ImageIO

/// On-device text recognition built on `VNRecognizeTextRequest`.
///
/// Returns ``RecognizedText`` (string + confidence + normalized bounding box) for each detected
/// line. Nothing leaves the device. Pair it with ``ReceiptParser`` to pull out totals and dates.
///
/// ```swift
/// let ocr = OCRService()
/// let lines = try ocr.recognizeText(in: cgImage)
/// let total = ReceiptParser.extractTotal(from: lines)
/// ```
public struct OCRService {
    /// Recognition accuracy. `.accurate` is best for documents; `.fast` for live/throughput.
    public var recognitionLevel: VNRequestTextRecognitionLevel
    /// Whether to apply language correction (spelling). Default `true`.
    public var usesLanguageCorrection: Bool
    /// Preferred recognition languages (BCP-47), or `nil` for the system default.
    public var recognitionLanguages: [String]?
    /// Minimum text height as a fraction of image height (filters tiny noise). Default `0`.
    public var minimumTextHeight: Float

    /// Create an OCR service.
    ///
    /// - Parameters:
    ///   - recognitionLevel: Accuracy/speed trade-off. Default `.accurate`.
    ///   - usesLanguageCorrection: Apply spelling correction. Default `true`.
    ///   - recognitionLanguages: Preferred languages. Default `nil` (system default).
    ///   - minimumTextHeight: Minimum text height fraction. Default `0`.
    public init(recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
                usesLanguageCorrection: Bool = true,
                recognitionLanguages: [String]? = nil,
                minimumTextHeight: Float = 0) {
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
        self.recognitionLanguages = recognitionLanguages
        self.minimumTextHeight = minimumTextHeight
    }

    /// Recognize text in an image.
    ///
    /// - Parameters:
    ///   - cgImage: The image to read.
    ///   - orientation: The image's orientation. Default `.up`.
    /// - Returns: Recognized lines, each with its top candidate string, confidence, and normalized
    ///   bounding box. Empty if no text is found.
    /// - Throws: Any error thrown by the Vision request handler.
    public func recognizeText(in cgImage: CGImage,
                              orientation: CGImagePropertyOrientation = .up) throws -> [RecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = usesLanguageCorrection
        request.recognitionLanguages = recognitionLanguages ?? []
        request.minimumTextHeight = minimumTextHeight

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedText(string: candidate.string,
                                  confidence: candidate.confidence,
                                  boundingBox: observation.boundingBox)
        }
    }

    /// Recognize text and return just the strings, in reading order.
    public func recognizeStrings(in cgImage: CGImage,
                                 orientation: CGImagePropertyOrientation = .up) throws -> [String] {
        try recognizeText(in: cgImage, orientation: orientation).map(\.string)
    }
}
