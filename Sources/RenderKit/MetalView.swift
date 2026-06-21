#if canImport(UIKit)
import SwiftUI
import MetalKit

/// A SwiftUI view that hosts an `MTKView` and draws a provided ``RenderPass`` each frame —
/// demonstrating SwiftUI ⇄ UIKit interop via `UIViewRepresentable`.
///
/// The view owns the drawable and command buffer lifecycle; your ``RenderPass`` only encodes its
/// pipeline, resource bindings, and draw calls. Mutate the pass's inputs (e.g.
/// ``FullScreenQuadPass/inputTexture``) and the next frame reflects them.
///
/// ```swift
/// let pass = FullScreenQuadPass(pipelineState: try context.pipelineState(fragment: "passthrough_fragment"))
/// pass.inputTexture = cameraTexture
/// MetalView(context: context, pass: pass)
///     .ignoresSafeArea()
/// ```
///
/// - Note: iOS only (it wraps `UIViewRepresentable`). Build it behind `#if canImport(UIKit)`.
public struct MetalView: UIViewRepresentable {
    private let context: MetalContext
    private let pass: RenderPass
    private let clearColor: MTLClearColor

    /// Create a Metal view.
    ///
    /// - Parameters:
    ///   - context: The Metal context providing the device and command queue.
    ///   - pass: The render pass drawn every frame.
    ///   - clearColor: Background clear colour. Default opaque black.
    public init(context: MetalContext,
                pass: RenderPass,
                clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)) {
        self.context = context
        self.pass = pass
        self.clearColor = clearColor
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(context: context, pass: pass)
    }

    public func makeUIView(context coordinatorContext: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.device)
        view.colorPixelFormat = .rgba8Unorm
        view.clearColor = clearColor
        view.framebufferOnly = false
        view.delegate = coordinatorContext.coordinator
        return view
    }

    public func updateUIView(_ uiView: MTKView, context coordinatorContext: Context) {
        coordinatorContext.coordinator.pass = pass
        uiView.setNeedsDisplay()
    }

    /// Drives drawing by forwarding `MTKView` callbacks to the render pass.
    public final class Coordinator: NSObject, MTKViewDelegate {
        private let context: MetalContext
        /// The render pass to encode each frame.
        public var pass: RenderPass

        init(context: MetalContext, pass: RenderPass) {
            self.context = context
            self.pass = pass
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = context.commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            pass.encode(into: encoder)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
#endif
