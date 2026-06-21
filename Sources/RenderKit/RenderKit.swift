import Foundation
import Metal

/// Reusable Metal render pipeline, shaders, and image filters.
///
/// ## Topics
/// ### Setup
/// - ``MetalContext``
/// - ``RenderError``
/// ### Passes & views
/// - ``RenderPass``
/// - ``FullScreenQuadPass``
/// - ``MetalView``
/// ### Image filters
/// - ``MetalFilter``
/// - ``PassthroughFilter``
/// - ``ColorAdjustFilter``
/// - ``GaussianBlurFilter``
/// - ``UnsharpMaskFilter``
/// ### Multi-frame
/// - ``FrameCompositor``
/// - ``BlendMode``
/// ### Pure math
/// - ``ColorAdjustment``
/// - ``GaussianKernel``
/// - ``ImageBridge``
///
/// Shader source ships in this target's resources (`Shaders.metal`) and is compiled at runtime by
/// ``MetalContext``. All GPU work degrades gracefully where no device exists (``MetalContext/shared``
/// is `nil`), while the colour/kernel math and CPU image bridging remain testable headless.
public enum RenderKit {
    /// Short description of the module.
    public static let info = "Metal shaders, render passes, image filters."

    /// Whether a Metal device is available in the current process (a GPU is present).
    public static var isMetalAvailable: Bool { MetalContext.shared != nil }
}
