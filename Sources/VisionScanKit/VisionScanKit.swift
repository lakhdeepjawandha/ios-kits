import CameraKit

/// Vision OCR, document/edge detection, Core ML wrappers, person/object segmentation.
///
/// Everything runs **on-device**. The text-parsing helpers (``ReceiptParser``) are pure and
/// unit-tested; the Vision/Core ML wrappers operate on `CGImage`s and are exercised by fixture-based
/// tests guarded for environments without the relevant capabilities.
///
/// ## Topics
/// ### Text
/// - ``OCRService``
/// - ``RecognizedText``
/// - ``ReceiptParser``
/// ### Documents
/// - ``DocumentScanner``
/// - ``DocumentCameraView``
/// ### Classification
/// - ``ImageClassifier``
/// - ``Classification``
/// - ``StubImageClassifier``
/// - ``CoreMLImageClassifier``
/// ### Segmentation
/// - ``Segmenter``
public enum VisionScanKit {
    public static let info = "Vision OCR, document detection, Core ML wrapper, segmentation."
}
