import Metal
import RenderKit

/// Errors thrown while setting up or driving a chart renderer.
public enum ChartRenderError: Error, Equatable {
    /// No Metal device is available (headless/CI).
    case noMetalContext
    /// The bundled `ChartShaders.metal` resource could not be found.
    case shaderSourceMissing
    /// Compiling the chart shader library failed. Carries the compiler message.
    case libraryCompilationFailed(String)
    /// A shader function was missing from the compiled library.
    case functionNotFound(String)
    /// Building the render pipeline state failed. Carries the message.
    case pipelineCreationFailed(String)
}

/// Draws chart geometry (``ChartVertex`` triangles from ``ChartGeometry``) with a single coloured
/// pipeline, on top of RenderKit's ``MetalContext``.
///
/// The renderer is format-aware: it caches one pipeline per colour pixel format, so it works
/// whether you target an `MTKView` (`.bgra8Unorm`) or an offscreen `.rgba8Unorm` texture (as the
/// tests do). Geometry is built on the CPU; ``encode(_:into:pixelFormat:)`` uploads it and issues
/// one draw call.
public final class CandlestickRenderer {
    /// The Metal context (shared device, queue) this renderer draws with.
    public let context: MetalContext
    private let library: MTLLibrary
    private let pipelineLock = NSLock()
    private var pipelines: [UInt: MTLRenderPipelineState] = [:]

    /// Create a renderer.
    ///
    /// - Parameter context: The Metal context. Defaults to ``MetalContext/shared``; throws
    ///   ``ChartRenderError/noMetalContext`` if there is no GPU.
    public init(context: MetalContext? = MetalContext.shared) throws {
        guard let context else { throw ChartRenderError.noMetalContext }
        self.context = context
        self.library = try Self.makeLibrary(device: context.device)
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "ChartShaders", withExtension: "metal")
            ?? bundle.url(forResource: "ChartShaders", withExtension: "metal", subdirectory: "Shaders")
        guard let url, let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw ChartRenderError.shaderSourceMissing
        }
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ChartRenderError.libraryCompilationFailed(error.localizedDescription)
        }
    }

    /// A cached, alpha-blended pipeline state for the given colour pixel format.
    public func pipeline(pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        pipelineLock.lock()
        if let cached = pipelines[pixelFormat.rawValue] {
            pipelineLock.unlock()
            return cached
        }
        pipelineLock.unlock()

        guard let vertex = library.makeFunction(name: "chart_vertex") else {
            throw ChartRenderError.functionNotFound("chart_vertex")
        }
        guard let fragment = library.makeFunction(name: "chart_fragment") else {
            throw ChartRenderError.functionNotFound("chart_fragment")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        // Standard source-over alpha blending for translucent gridlines / crosshair.
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let state: MTLRenderPipelineState
        do {
            state = try context.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw ChartRenderError.pipelineCreationFailed(error.localizedDescription)
        }
        pipelineLock.lock()
        pipelines[pixelFormat.rawValue] = state
        pipelineLock.unlock()
        return state
    }

    /// Encode a draw call for the given vertices into an existing render command encoder.
    ///
    /// - Parameters:
    ///   - vertices: Triangle-list vertices in NDC (from ``ChartGeometry``). No-op if empty.
    ///   - encoder: The active render command encoder (the caller owns its lifecycle).
    ///   - pixelFormat: The colour attachment format the encoder targets.
    public func encode(_ vertices: [ChartVertex],
                       into encoder: MTLRenderCommandEncoder,
                       pixelFormat: MTLPixelFormat) throws {
        guard !vertices.isEmpty else { return }
        let length = vertices.count * MemoryLayout<ChartVertex>.stride
        guard let buffer = context.device.makeBuffer(bytes: vertices, length: length, options: .storageModeShared) else {
            return
        }
        let state = try pipeline(pixelFormat: pixelFormat)
        encoder.setRenderPipelineState(state)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }
}
