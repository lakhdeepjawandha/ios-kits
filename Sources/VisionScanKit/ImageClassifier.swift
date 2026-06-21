import Vision
import CoreML
import CoreGraphics
import ImageIO

/// A single classification result: a label and its confidence.
public struct Classification: Equatable, Sendable {
    /// The class label (model-defined identifier).
    public let identifier: String
    /// Confidence in `0...1`.
    public let confidence: Float

    /// Create a classification.
    public init(identifier: String, confidence: Float) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

/// A generic on-device image classifier. Conform your own (or use ``CoreMLImageClassifier``) and
/// keep call sites model-agnostic — this is the swap seam for dropping in a real `.mlmodel`.
public protocol ImageClassifier {
    /// Classify an image into labelled results, most confident first.
    ///
    /// - Parameters:
    ///   - cgImage: The image to classify.
    ///   - orientation: The image's orientation.
    /// - Returns: Classifications sorted by descending confidence.
    func classify(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [Classification]
}

public extension ImageClassifier {
    /// Classify with a default `.up` orientation.
    func classify(_ cgImage: CGImage) async throws -> [Classification] {
        try await classify(cgImage, orientation: .up)
    }
}

/// Keep the top-`k` classifications by confidence. Pure and unit-tested.
///
/// - Parameters:
///   - classifications: Input results in any order.
///   - k: Maximum number to keep (`<= 0` returns empty).
/// - Returns: The `k` highest-confidence results, descending.
public func topK(_ classifications: [Classification], k: Int) -> [Classification] {
    guard k > 0 else { return [] }
    return Array(classifications.sorted { $0.confidence > $1.confidence }.prefix(k))
}

/// A placeholder classifier that returns a fixed result without any model. Use it to build and test
/// UI/flows before a real model exists; swap in ``CoreMLImageClassifier`` later with no call-site
/// changes.
public struct StubImageClassifier: ImageClassifier {
    /// The canned results returned for any image.
    public let cannedResults: [Classification]

    /// Create a stub.
    ///
    /// - Parameter cannedResults: Results to return. Default a single low-confidence `"unknown"`.
    public init(cannedResults: [Classification] = [Classification(identifier: "unknown", confidence: 0.0)]) {
        self.cannedResults = cannedResults
    }

    public func classify(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [Classification] {
        cannedResults
    }
}

/// A Core ML–backed classifier driven through Vision (`VNCoreMLRequest`).
///
/// ## Dropping in a real model
/// 1. Add a classifier `.mlmodel` (e.g. an image-classification model) to your app target — Xcode
///    compiles it to a `.mlmodelc` and generates a Swift class, or you can keep the raw model as a
///    package resource and compile at runtime.
/// 2. Load it and construct the classifier:
///    ```swift
///    // From a generated class:
///    let classifier = try CoreMLImageClassifier(model: MyModel(configuration: .init()).model)
///
///    // From a compiled .mlmodelc bundled as a resource:
///    let url = Bundle.module.url(forResource: "MyModel", withExtension: "mlmodelc")!
///    let classifier = try CoreMLImageClassifier(contentsOf: url)
///    ```
/// 3. Use it anywhere an ``ImageClassifier`` is expected — no other code changes.
///
/// No model ships with this package, so use ``StubImageClassifier`` until you add one.
public struct CoreMLImageClassifier: ImageClassifier {
    private let visionModel: VNCoreMLModel
    /// How Vision crops/scales the image to the model's input. Default `.centerCrop`.
    public var imageCropAndScaleOption: VNImageCropAndScaleOption

    /// Wrap an already-loaded `MLModel`.
    ///
    /// - Parameters:
    ///   - model: The Core ML model.
    ///   - imageCropAndScaleOption: Crop/scale strategy. Default `.centerCrop`.
    /// - Throws: ``VisionScanError/modelLoadFailed(_:)`` if Vision can't wrap the model.
    public init(model: MLModel, imageCropAndScaleOption: VNImageCropAndScaleOption = .centerCrop) throws {
        do {
            self.visionModel = try VNCoreMLModel(for: model)
        } catch {
            throw VisionScanError.modelLoadFailed(error.localizedDescription)
        }
        self.imageCropAndScaleOption = imageCropAndScaleOption
    }

    /// Load a compiled model (`.mlmodelc`) from a URL.
    ///
    /// - Parameters:
    ///   - url: URL of a compiled `.mlmodelc`.
    ///   - imageCropAndScaleOption: Crop/scale strategy. Default `.centerCrop`.
    /// - Throws: ``VisionScanError/modelLoadFailed(_:)`` if loading or wrapping fails.
    public init(contentsOf url: URL, imageCropAndScaleOption: VNImageCropAndScaleOption = .centerCrop) throws {
        let model: MLModel
        do {
            model = try MLModel(contentsOf: url)
        } catch {
            throw VisionScanError.modelLoadFailed(error.localizedDescription)
        }
        try self.init(model: model, imageCropAndScaleOption: imageCropAndScaleOption)
    }

    public func classify(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [Classification] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = imageCropAndScaleOption

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])

        guard let observations = request.results as? [VNClassificationObservation] else {
            throw VisionScanError.classificationFailed
        }
        return observations
            .map { Classification(identifier: $0.identifier, confidence: $0.confidence) }
            .sorted { $0.confidence > $1.confidence }
    }
}
