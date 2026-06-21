import Metal

/// A unit of GPU drawing that encodes itself into a render command encoder.
///
/// Conformers set their pipeline state, bind resources, and issue draw calls inside ``encode(into:)``.
/// ``MetalView`` calls this once per frame with an encoder configured for the drawable;
/// ``FullScreenQuadPass`` is the common base for image-style passes.
public protocol RenderPass: AnyObject {
    /// Encode draw commands into the given encoder. The caller owns the encoder's lifetime
    /// (creation, `endEncoding`, and presentation).
    func encode(into encoder: MTLRenderCommandEncoder)
}

/// A base render pass that draws a single full-screen triangle with a fragment shader, optionally
/// sampling an input texture. Subclass it (or set ``configureFragment``) to bind uniforms.
///
/// The geometry comes entirely from `fullscreen_vertex` in the shader, so there is no vertex buffer
/// to manage — just supply a pipeline state built from a full-screen fragment shader and an
/// ``inputTexture``.
open class FullScreenQuadPass: RenderPass {
    /// The pipeline state used to draw the quad.
    public let pipelineState: MTLRenderPipelineState
    /// The texture bound to fragment texture slot `0`, if any.
    public var inputTexture: MTLTexture?
    /// Optional hook to bind additional fragment uniforms/textures before the draw call.
    public var configureFragment: ((MTLRenderCommandEncoder) -> Void)?

    /// Create a full-screen pass.
    ///
    /// - Parameters:
    ///   - pipelineState: Pipeline built from `fullscreen_vertex` + a full-screen fragment shader.
    ///   - inputTexture: Texture bound at fragment index `0`. Default `nil`.
    public init(pipelineState: MTLRenderPipelineState, inputTexture: MTLTexture? = nil) {
        self.pipelineState = pipelineState
        self.inputTexture = inputTexture
    }

    open func encode(into encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipelineState)
        if let inputTexture {
            encoder.setFragmentTexture(inputTexture, index: 0)
        }
        configureFragment?(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
