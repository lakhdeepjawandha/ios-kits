import Metal
import CoreGraphics
import simd

/// Memory layout mirror of `ColorAdjustUniforms` in `Shaders.metal` (three packed floats).
struct ColorAdjustUniforms {
    var brightness: Float
    var contrast: Float
    var saturation: Float
}

/// A GPU image filter: transforms an input texture into a new output texture, encoding its work into
/// the supplied command buffer.
///
/// Filters are composable — run a chain with ``MetalContext/apply(_:to:)-(_,MTLTexture)``. Each
/// filter allocates its own output, so chains never alias their input.
public protocol MetalFilter {
    /// Encode this filter and return its output texture.
    ///
    /// - Parameters:
    ///   - input: The source texture.
    ///   - context: The Metal context (device, pipelines, allocation helpers).
    ///   - commandBuffer: The command buffer to encode into (committed by the chain runner).
    /// - Returns: A freshly-allocated output texture, same size as `input`.
    func apply(to input: MTLTexture, in context: MetalContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture
}

/// Copies the input through the `passthrough_fragment` shader unchanged. Useful as a no-op step or
/// to force a format/size normalization render.
public struct PassthroughFilter: MetalFilter {
    public init() {}

    public func apply(to input: MTLTexture, in context: MetalContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        let output = try context.makeColorTexture(width: input.width, height: input.height)
        let pipeline = try context.pipelineState(fragment: "passthrough_fragment")
        try context.renderFullScreen(pipeline: pipeline, into: output, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(input, index: 0)
        }
        return output
    }
}

/// Brightness / contrast / saturation adjustment via `color_adjust_fragment`.
/// See ``ColorAdjustment`` for the exact (CPU-mirrored) math.
public struct ColorAdjustFilter: MetalFilter {
    /// The adjustment to apply.
    public var adjustment: ColorAdjustment

    /// Create a colour-adjust filter from a ``ColorAdjustment``.
    public init(_ adjustment: ColorAdjustment) {
        self.adjustment = adjustment
    }

    /// Create a colour-adjust filter from individual parameters (identity `1` each).
    public init(brightness: Float = 1, contrast: Float = 1, saturation: Float = 1) {
        self.adjustment = ColorAdjustment(brightness: brightness, contrast: contrast, saturation: saturation)
    }

    public func apply(to input: MTLTexture, in context: MetalContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        let output = try context.makeColorTexture(width: input.width, height: input.height)
        let pipeline = try context.pipelineState(fragment: "color_adjust_fragment")
        var uniforms = ColorAdjustUniforms(brightness: adjustment.brightness,
                                           contrast: adjustment.contrast,
                                           saturation: adjustment.saturation)
        try context.renderFullScreen(pipeline: pipeline, into: output, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(input, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ColorAdjustUniforms>.stride, index: 0)
        }
        return output
    }
}

/// Separable Gaussian blur via two `gaussian_blur_fragment` passes (horizontal then vertical).
/// The kernel weights come from ``GaussianKernel`` and are normalized, so the blur preserves overall
/// brightness.
public struct GaussianBlurFilter: MetalFilter {
    /// Blur radius in taps.
    public var radius: Int
    /// Standard deviation; `nil` derives a sensible default from `radius`.
    public var sigma: Float?

    /// Create a Gaussian blur.
    ///
    /// - Parameters:
    ///   - radius: Samples per side. `0` is a no-op (identity kernel).
    ///   - sigma: Standard deviation. `nil` uses `max(1, radius/2)`.
    public init(radius: Int, sigma: Float? = nil) {
        self.radius = radius
        self.sigma = sigma
    }

    public func apply(to input: MTLTexture, in context: MetalContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        let kernel = GaussianKernel(radius: radius, sigma: sigma)
        let width = input.width
        let height = input.height
        let pipeline = try context.pipelineState(fragment: "gaussian_blur_fragment")

        var weights = kernel.weights
        var radiusValue = Int32(kernel.radius)
        let weightsLength = weights.count * MemoryLayout<Float>.stride

        let horizontal = try context.makeColorTexture(width: width, height: height)
        var offsetH = SIMD2<Float>(1 / Float(width), 0)
        try context.renderFullScreen(pipeline: pipeline, into: horizontal, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(input, index: 0)
            encoder.setFragmentBytes(&weights, length: weightsLength, index: 0)
            encoder.setFragmentBytes(&radiusValue, length: MemoryLayout<Int32>.stride, index: 1)
            encoder.setFragmentBytes(&offsetH, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
        }

        let output = try context.makeColorTexture(width: width, height: height)
        var offsetV = SIMD2<Float>(0, 1 / Float(height))
        try context.renderFullScreen(pipeline: pipeline, into: output, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(horizontal, index: 0)
            encoder.setFragmentBytes(&weights, length: weightsLength, index: 0)
            encoder.setFragmentBytes(&radiusValue, length: MemoryLayout<Int32>.stride, index: 1)
            encoder.setFragmentBytes(&offsetV, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
        }
        return output
    }
}

/// Unsharp-mask sharpen: blurs the input, then adds back a scaled high-frequency difference via
/// `unsharp_fragment`. See ``unsharpMask(input:blurred:amount:)`` for the per-channel math.
public struct UnsharpMaskFilter: MetalFilter {
    /// Blur radius used to build the mask.
    public var radius: Int
    /// Blur standard deviation (`nil` = default).
    public var sigma: Float?
    /// Sharpening strength (`0` = no change; typical values `0.5...2`).
    public var amount: Float

    /// Create an unsharp-mask filter.
    ///
    /// - Parameters:
    ///   - radius: Blur radius for the mask. Default `2`.
    ///   - sigma: Blur standard deviation. Default `nil`.
    ///   - amount: Sharpening strength. Default `0.8`.
    public init(radius: Int = 2, sigma: Float? = nil, amount: Float = 0.8) {
        self.radius = radius
        self.sigma = sigma
        self.amount = amount
    }

    public func apply(to input: MTLTexture, in context: MetalContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        let blurred = try GaussianBlurFilter(radius: radius, sigma: sigma)
            .apply(to: input, in: context, commandBuffer: commandBuffer)

        let output = try context.makeColorTexture(width: input.width, height: input.height)
        let pipeline = try context.pipelineState(fragment: "unsharp_fragment")
        var amountValue = amount
        try context.renderFullScreen(pipeline: pipeline, into: output, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(input, index: 0)
            encoder.setFragmentTexture(blurred, index: 1)
            encoder.setFragmentBytes(&amountValue, length: MemoryLayout<Float>.stride, index: 0)
        }
        return output
    }
}

public extension MetalContext {

    /// Run a chain of filters over an input texture on a single command buffer.
    ///
    /// - Parameters:
    ///   - filters: Filters applied in order. An empty array returns `input` unchanged.
    ///   - input: The source texture.
    /// - Returns: The final output texture (or `input` if `filters` is empty).
    func apply(_ filters: [MetalFilter], to input: MTLTexture) throws -> MTLTexture {
        guard !filters.isEmpty else { return input }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RenderError.commandEncodingFailed
        }
        var current = input
        for filter in filters {
            current = try filter.apply(to: current, in: self, commandBuffer: commandBuffer)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return current
    }

    /// One-shot: run a filter chain on a `CGImage` and return the resulting `CGImage`.
    ///
    /// Uploads the image to a texture, runs ``apply(_:to:)-(_,MTLTexture)``, and reads the result
    /// back. An empty chain returns a faithful copy of the input.
    ///
    /// - Parameters:
    ///   - filters: Filters applied in order.
    ///   - cgImage: The source image.
    /// - Returns: The processed image.
    func apply(_ filters: [MetalFilter], to cgImage: CGImage) throws -> CGImage {
        let input = try makeTexture(from: cgImage)
        let output = try apply(filters.isEmpty ? [PassthroughFilter()] : filters, to: input)
        return try makeCGImage(from: output)
    }
}
