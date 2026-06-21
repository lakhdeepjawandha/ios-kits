import Foundation

/// Errors thrown by VisionScanKit.
public enum VisionScanError: Error, Equatable {
    /// No Core ML model has been provided to the classifier.
    case noModel
    /// The Core ML model could not be loaded or wrapped for Vision. Carries a message.
    case modelLoadFailed(String)
    /// Image classification produced no usable results.
    case classificationFailed
    /// Person segmentation produced no mask.
    case segmentationFailed
    /// No document/rectangle could be detected in the image.
    case noDocumentDetected
    /// Perspective correction or rendering failed.
    case imageProcessingFailed
}

extension VisionScanError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noModel:                  return "No Core ML model was provided."
        case let .modelLoadFailed(m):   return "Failed to load the Core ML model: \(m)"
        case .classificationFailed:     return "Image classification produced no results."
        case .segmentationFailed:       return "Person segmentation produced no mask."
        case .noDocumentDetected:       return "No document was detected in the image."
        case .imageProcessingFailed:    return "Image processing failed."
        }
    }
}
