import Foundation
import Metal

/// Errors thrown by RenderKit's Metal setup and rendering.
public enum RenderError: Error, Equatable {
    /// No Metal device is available (e.g. a CI runner or a Simulator without GPU support).
    case noMetalDevice
    /// `MTLDevice.makeCommandQueue()` returned `nil`.
    case commandQueueCreationFailed
    /// The bundled `Shaders.metal` resource could not be located.
    case shaderSourceMissing
    /// Compiling the Metal shader library failed. Carries the compiler message.
    case libraryCompilationFailed(String)
    /// A named shader function was not found in the compiled library.
    case functionNotFound(String)
    /// A `MTLRenderPipelineState` could not be created. Carries the underlying message.
    case pipelineCreationFailed(String)
    /// A texture could not be allocated.
    case textureCreationFailed
    /// A command buffer or encoder could not be created.
    case commandEncodingFailed
    /// Reading pixels back from a texture failed (e.g. an incompatible storage mode).
    case textureReadFailed
}

/// The shared Metal objects RenderKit needs: a `MTLDevice`, a `MTLCommandQueue`, and the compiled
/// shader `MTLLibrary`.
///
/// `MetalContext` is **failable on purpose**: on machines without a GPU (CI, some headless
/// environments) there is no Metal device, so ``shared`` is `nil` and GPU work is simply skipped.
/// Pure logic (colour math, kernel generation, CPU image bridging) lives elsewhere and never needs
/// a context, so it remains fully testable headless.
///
/// The shader library is compiled **at runtime** from the bundled `Shaders.metal` source via
/// `device.makeLibrary(source:)`. This sidesteps any dependency on the build system compiling
/// `.metal` files and keeps the shaders editable as plain resources.
public final class MetalContext {
    /// The Metal device backing all GPU work.
    public let device: MTLDevice
    /// A reusable command queue.
    public let commandQueue: MTLCommandQueue
    /// The compiled shader library (see `Shaders.metal`).
    public let library: MTLLibrary

    private let pipelineLock = NSLock()
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    /// A process-wide shared context, or `nil` when no Metal device is available.
    ///
    /// Use this in app code and as the availability gate in tests:
    /// ```swift
    /// guard let context = MetalContext.shared else { throw XCTSkip("No GPU") }
    /// ```
    public static let shared: MetalContext? = try? MetalContext()

    /// Create a context on the system default device.
    ///
    /// - Throws: ``RenderError/noMetalDevice`` if there is no GPU, or a compilation error.
    public convenience init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        try self.init(device: device)
    }

    /// Create a context on a specific device. Useful for tests that pick a device explicitly.
    ///
    /// - Parameter device: The Metal device to use.
    /// - Throws: ``RenderError`` if the command queue or shader library cannot be created.
    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RenderError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        self.library = try Self.makeLibrary(device: device)
    }

    // MARK: - Library

    /// Load the bundled shader source and compile it into a library.
    static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        let source = try shaderSource()
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RenderError.libraryCompilationFailed(error.localizedDescription)
        }
    }

    /// The text of the bundled `Shaders.metal`. Looks in the bundle root and a `Shaders`
    /// subdirectory to be robust to how the resource is copied.
    static func shaderSource() throws -> String {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "Shaders", withExtension: "metal")
            ?? bundle.url(forResource: "Shaders", withExtension: "metal", subdirectory: "Shaders")
        guard let url else { throw RenderError.shaderSourceMissing }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Pipelines

    /// Build a render pipeline state for a full-screen pass.
    ///
    /// - Parameters:
    ///   - vertexFunction: Vertex function name. Defaults to the shared `"fullscreen_vertex"`.
    ///   - fragmentFunction: Fragment function name.
    ///   - pixelFormat: Colour attachment pixel format. Defaults to `.rgba8Unorm`.
    /// - Returns: A compiled pipeline state.
    /// - Throws: ``RenderError/functionNotFound(_:)`` or ``RenderError/pipelineCreationFailed(_:)``.
    public func makePipelineState(vertexFunction: String = "fullscreen_vertex",
                                  fragmentFunction: String,
                                  pixelFormat: MTLPixelFormat = .rgba8Unorm) throws -> MTLRenderPipelineState {
        guard let vertex = library.makeFunction(name: vertexFunction) else {
            throw RenderError.functionNotFound(vertexFunction)
        }
        guard let fragment = library.makeFunction(name: fragmentFunction) else {
            throw RenderError.functionNotFound(fragmentFunction)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RenderError.pipelineCreationFailed(error.localizedDescription)
        }
    }

    /// A cached pipeline state for a full-screen fragment shader. Repeated calls with the same
    /// arguments return the same object.
    ///
    /// - Parameters:
    ///   - fragment: Fragment function name.
    ///   - pixelFormat: Colour attachment pixel format. Defaults to `.rgba8Unorm`.
    public func pipelineState(fragment: String,
                              pixelFormat: MTLPixelFormat = .rgba8Unorm) throws -> MTLRenderPipelineState {
        let key = "fullscreen_vertex|\(fragment)|\(pixelFormat.rawValue)"
        pipelineLock.lock()
        if let cached = pipelineCache[key] {
            pipelineLock.unlock()
            return cached
        }
        pipelineLock.unlock()

        let state = try makePipelineState(fragmentFunction: fragment, pixelFormat: pixelFormat)
        pipelineLock.lock()
        pipelineCache[key] = state
        pipelineLock.unlock()
        return state
    }

    // MARK: - Encoding helpers

    /// Encode a single full-screen pass that renders into `output`.
    ///
    /// Sets the pipeline, invokes `configure` to bind textures/uniforms, then draws the three-vertex
    /// full-screen triangle. The output's existing contents are discarded.
    ///
    /// - Parameters:
    ///   - pipeline: The pipeline state to use.
    ///   - output: The colour texture to render into.
    ///   - commandBuffer: The command buffer to encode into.
    ///   - configure: Closure to bind fragment textures and bytes on the encoder.
    /// - Throws: ``RenderError/commandEncodingFailed`` if the encoder cannot be created.
    public func renderFullScreen(pipeline: MTLRenderPipelineState,
                                 into output: MTLTexture,
                                 commandBuffer: MTLCommandBuffer,
                                 configure: (MTLRenderCommandEncoder) -> Void) throws {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = output
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw RenderError.commandEncodingFailed
        }
        encoder.setRenderPipelineState(pipeline)
        configure(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
