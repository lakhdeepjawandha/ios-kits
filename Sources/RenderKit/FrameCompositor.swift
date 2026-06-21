import Metal

/// Accumulates and blends a sequence of frames on the GPU into a single result texture — the basis
/// for long-exposure capture and other multi-frame effects.
///
/// Feed frames in with ``add(_:)``; read the running result from ``result``. The blend math is
/// defined by ``BlendMode`` and matches the `composite_fragment` shader (and the CPU reference in
/// ``BlendMode/blend(accumulated:incoming:sampleCount:)``).
///
/// The accumulator starts zero-cleared, so the first frame passes through unchanged in every mode.
/// A 16-bit-float accumulator is used so that long `average`/`additive` runs don't lose precision.
///
/// ```swift
/// let compositor = try FrameCompositor(context: ctx, width: w, height: h, mode: .average)
/// for frame in frames { try compositor.add(frame) }
/// let longExposure = compositor.result   // arithmetic mean of all frames
/// ```
public final class FrameCompositor {
    private let context: MetalContext
    /// Output width in pixels.
    public let width: Int
    /// Output height in pixels.
    public let height: Int
    /// How incoming frames are blended into the accumulator.
    public let mode: BlendMode

    private var accumulator: MTLTexture
    private var scratch: MTLTexture
    private let pipeline: MTLRenderPipelineState

    /// Number of frames accumulated so far.
    public private(set) var frameCount = 0

    /// The current composited result. Same object identity is preserved across reads until the next
    /// ``add(_:)`` or ``reset()``.
    public var result: MTLTexture { accumulator }

    /// Create a compositor.
    ///
    /// - Parameters:
    ///   - context: The Metal context.
    ///   - width: Output width in pixels.
    ///   - height: Output height in pixels.
    ///   - mode: Blend mode. Default ``BlendMode/average``.
    /// - Throws: ``RenderError`` if textures or the pipeline can't be created.
    public init(context: MetalContext, width: Int, height: Int, mode: BlendMode = .average) throws {
        self.context = context
        self.width = width
        self.height = height
        self.mode = mode
        // The accumulator must be both renderable and samplable; 16-bit float keeps precision.
        self.accumulator = try context.makeColorTexture(width: width, height: height, pixelFormat: .rgba16Float)
        self.scratch = try context.makeColorTexture(width: width, height: height, pixelFormat: .rgba16Float)
        self.pipeline = try context.pipelineState(fragment: "composite_fragment", pixelFormat: .rgba16Float)
        try clear(accumulator)
    }

    /// Blend a frame into the accumulator.
    ///
    /// - Parameter frame: The incoming frame texture (any size; sampled with normalized coords).
    /// - Throws: ``RenderError`` if encoding fails.
    public func add(_ frame: MTLTexture) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw RenderError.commandEncodingFailed
        }
        var modeValue = Int32(mode.rawValue)
        var countValue = Int32(frameCount)
        try context.renderFullScreen(pipeline: pipeline, into: scratch, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(accumulator, index: 0)
            encoder.setFragmentTexture(frame, index: 1)
            encoder.setFragmentBytes(&modeValue, length: MemoryLayout<Int32>.stride, index: 0)
            encoder.setFragmentBytes(&countValue, length: MemoryLayout<Int32>.stride, index: 1)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        swap(&accumulator, &scratch)
        frameCount += 1
    }

    /// Clear the accumulator and reset the frame count.
    public func reset() throws {
        frameCount = 0
        try clear(accumulator)
    }

    /// Read the accumulated result back as 8-bit RGBA bytes (R,G,B,A, values clamped to `0...1`).
    ///
    /// - Returns: `width * height * 4` bytes.
    public func resultBytes() -> [UInt8] {
        var halfBytes = [UInt16](repeating: 0, count: width * height * 4)
        halfBytes.withUnsafeMutableBytes { raw in
            accumulator.getBytes(raw.baseAddress!,
                                 bytesPerRow: width * 4 * MemoryLayout<UInt16>.stride,
                                 from: MTLRegionMake2D(0, 0, width, height),
                                 mipmapLevel: 0)
        }
        return halfBytes.map { half in
            let value = Float(float16: half)
            return UInt8(max(0, min(1, value)) * 255 + 0.5)
        }
    }

    private func clear(_ texture: MTLTexture) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw RenderError.commandEncodingFailed
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw RenderError.commandEncodingFailed
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

private extension Float {
    /// Decode an IEEE-754 half-precision (`rgba16Float`) value to `Float`.
    init(float16 bits: UInt16) {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = UInt32(bits & 0x7C00) >> 10
        let mantissa = UInt32(bits & 0x03FF)

        if exponent == 0 {
            if mantissa == 0 {
                self = Float(bitPattern: sign)            // ±0
            } else {
                // Subnormal: normalize.
                var e: UInt32 = 0
                var m = mantissa
                while (m & 0x0400) == 0 { m <<= 1; e += 1 }
                m &= 0x03FF
                let exp = UInt32(127 - 15 - e)
                self = Float(bitPattern: sign | (exp << 23) | (m << 13))
            }
        } else if exponent == 0x1F {
            self = Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))  // Inf/NaN
        } else {
            let exp = exponent &- 15 &+ 127
            self = Float(bitPattern: sign | (exp << 23) | (mantissa << 13))
        }
    }
}
