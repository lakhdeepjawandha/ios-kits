#if canImport(UIKit)
import SwiftUI
import MetalKit
import AVFoundation
import RenderKit

/// A low-latency Metal preview that renders the controller's live `CVPixelBuffer` frames.
///
/// Frames are wrapped as Metal textures via a `CVMetalTextureCache` (zero-copy) and drawn with
/// RenderKit's full-screen passthrough pipeline. Rendering runs continuously at up to 60 fps and
/// always shows the most recent frame, so the preview stays responsive even if processing lags.
public struct MetalCameraPreview: UIViewRepresentable {
    private let controller: CaptureController

    /// Create a preview bound to a capture controller.
    public init(controller: CaptureController) {
        self.controller = controller
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.metalContext?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.coordinator.start()
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {}

    /// Bridges camera frames to Metal textures and draws them.
    public final class Coordinator: NSObject, MTKViewDelegate {
        let metalContext: MetalContext?
        private let controller: CaptureController
        private let pipeline: MTLRenderPipelineState?
        private var textureCache: CVMetalTextureCache?
        private var latestTexture: MTLTexture?
        private var retainedCVTexture: CVMetalTexture?
        private var frameTask: Task<Void, Never>?

        init(controller: CaptureController) {
            self.controller = controller
            self.metalContext = MetalContext.shared
            self.pipeline = try? metalContext?.pipelineState(fragment: "passthrough_fragment",
                                                             pixelFormat: .bgra8Unorm)
            if let device = metalContext?.device {
                var cache: CVMetalTextureCache?
                CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
                self.textureCache = cache
            }
            super.init()
        }

        /// Begin consuming the controller's frame stream.
        func start() {
            frameTask?.cancel()
            frameTask = Task { [weak self] in
                guard let self else { return }
                for await pixelBuffer in await controller.frames() {
                    self.ingest(pixelBuffer)
                }
            }
        }

        deinit { frameTask?.cancel() }

        private func ingest(_ pixelBuffer: CVPixelBuffer) {
            guard let textureCache else { return }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            var cvTexture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil,
                .bgra8Unorm, width, height, 0, &cvTexture)
            guard status == kCVReturnSuccess, let cvTexture,
                  let texture = CVMetalTextureGetTexture(cvTexture) else { return }
            // Retain the CVMetalTexture until the next frame so its backing isn't reclaimed.
            retainedCVTexture = cvTexture
            latestTexture = texture
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let metalContext, let pipeline,
                  let texture = latestTexture,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = metalContext.commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            let pass = FullScreenQuadPass(pipelineState: pipeline, inputTexture: texture)
            pass.encode(into: encoder)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
#endif
