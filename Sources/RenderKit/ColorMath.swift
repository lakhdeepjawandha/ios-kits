import simd

/// Rec. 709 luminance weights, used everywhere a single brightness value must be derived from RGB.
///
/// These exact coefficients are mirrored in `Shaders.metal` so the CPU reference math and the GPU
/// shaders agree to within floating-point tolerance.
public enum Luma {
    /// Linear Rec. 709 luma coefficients (R, G, B).
    public static let rec709 = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    /// Perceived luminance of an RGB triple.
    public static func luminance(_ rgb: SIMD3<Float>) -> Float {
        dot(rgb, rec709)
    }
}

/// Brightness / contrast / saturation adjustment, expressed as pure math so it can be unit-tested
/// without a GPU. The `color_adjust_fragment` shader applies the identical pipeline.
///
/// All three parameters are multiplicative with an identity of `1`:
/// - `brightness` scales RGB about black (`1` = unchanged, `0` = black, `>1` = brighter).
/// - `contrast` scales RGB about mid-grey `0.5` (`1` = unchanged, `0` = flat grey).
/// - `saturation` interpolates between luminance-grey and full colour (`1` = unchanged,
///   `0` = greyscale, `>1` = more saturated).
///
/// The operations are applied in order — brightness, then contrast, then saturation — and the
/// result is clamped to `0...1`.
public struct ColorAdjustment: Equatable, Sendable {
    /// Brightness multiplier (identity `1`).
    public var brightness: Float
    /// Contrast multiplier about mid-grey (identity `1`).
    public var contrast: Float
    /// Saturation multiplier (identity `1`, `0` = greyscale).
    public var saturation: Float

    /// The identity adjustment (no visible change).
    public static let identity = ColorAdjustment(brightness: 1, contrast: 1, saturation: 1)

    /// Create a colour adjustment.
    ///
    /// - Parameters:
    ///   - brightness: Brightness multiplier. Default `1`.
    ///   - contrast: Contrast multiplier. Default `1`.
    ///   - saturation: Saturation multiplier. Default `1`.
    public init(brightness: Float = 1, contrast: Float = 1, saturation: Float = 1) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
    }

    /// Whether this adjustment is a no-op.
    public var isIdentity: Bool { self == .identity }

    /// Apply the adjustment to a single linear RGB triple, returning a clamped result.
    ///
    /// - Parameter rgb: Input RGB in `0...1`.
    /// - Returns: Adjusted RGB clamped to `0...1`.
    public func apply(to rgb: SIMD3<Float>) -> SIMD3<Float> {
        var c = rgb * brightness
        c = (c - 0.5) * contrast + 0.5
        let lum = Luma.luminance(c)
        c = mix(SIMD3<Float>(repeating: lum), c, t: saturation)
        return clamp(c, min: SIMD3<Float>(repeating: 0), max: SIMD3<Float>(repeating: 1))
    }
}

/// A 1-D Gaussian blur kernel: a one-sided list of normalized weights used by the separable
/// `gaussian_blur_fragment` shader (horizontal then vertical pass).
///
/// `weights[0]` is the centre tap; `weights[i]` is the weight at offset `±i`. The kernel is
/// normalized so that `weights[0] + 2·Σ weights[1...] == 1`, which means blurring a flat colour
/// returns the same colour (brightness-preserving).
public struct GaussianKernel: Equatable, Sendable {
    /// One-sided, normalized weights. Length is `radius + 1`.
    public let weights: [Float]
    /// The blur radius in taps (number of samples on each side of centre).
    public let radius: Int

    /// Build a Gaussian kernel.
    ///
    /// - Parameters:
    ///   - radius: Samples on each side of centre. Values `<= 0` yield a 1-tap identity kernel.
    ///   - sigma: Standard deviation. When `nil`, defaults to `max(1, radius/2)`.
    public init(radius: Int, sigma: Float? = nil) {
        let r = Swift.max(0, radius)
        self.radius = r
        guard r > 0 else { self.weights = [1]; return }

        let s = sigma ?? Swift.max(1, Float(r) / 2)
        let twoSigmaSq = 2 * s * s
        var raw = [Float](repeating: 0, count: r + 1)
        for i in 0...r {
            raw[i] = exp(-Float(i * i) / twoSigmaSq)
        }
        // Total mass counts the centre once and every side tap twice.
        let total = raw[0] + 2 * raw[1...].reduce(0, +)
        self.weights = raw.map { $0 / total }
    }

    /// Sum of the full (two-sided) kernel: `weights[0] + 2·Σ weights[1...]`. Should be ≈ 1.
    public var normalizedSum: Float {
        weights[0] + 2 * weights[1...].reduce(0, +)
    }
}

/// Per-channel unsharp-mask combine: `output = input + amount · (input − blurred)`, clamped.
///
/// Mirrors the `unsharp_fragment` shader. Sharpening a flat region (where `input == blurred`) is a
/// no-op, which makes it convenient to verify on the GPU with a solid-colour image.
///
/// - Parameters:
///   - input: Original sample.
///   - blurred: Blurred sample.
///   - amount: Sharpening strength (`0` = no change).
/// - Returns: Sharpened value clamped to `0...1`.
public func unsharpMask(input: Float, blurred: Float, amount: Float) -> Float {
    Swift.min(1, Swift.max(0, input + amount * (input - blurred)))
}

/// How ``FrameCompositor`` combines an incoming frame with the running accumulator.
///
/// The pure ``blend(accumulated:incoming:sampleCount:)`` function below is the reference
/// implementation; the `composite_fragment` shader performs the identical math per pixel.
public enum BlendMode: Int, Sendable, CaseIterable {
    /// Incremental arithmetic mean of all frames (the basis for long-exposure averaging).
    case average = 0
    /// Sum of frames, clamped to `1` (brightens; classic light-trail look).
    case additive = 1
    /// Per-channel maximum (keeps the brightest sample; star-trail / light-painting).
    case lighten = 2
    /// Screen blend: `1 − (1−a)(1−b)` (brightens without harsh clipping).
    case screen = 3

    /// Blend one channel of an incoming sample into the accumulator.
    ///
    /// - Parameters:
    ///   - accumulated: Current accumulator value (`0` before the first frame).
    ///   - incoming: The new frame's channel value.
    ///   - sampleCount: Number of frames already accumulated (0 for the first frame). Only the
    ///     `average` mode uses this, to weight the incremental mean correctly.
    /// - Returns: The new accumulator value.
    public func blend(accumulated a: Float, incoming b: Float, sampleCount: Int) -> Float {
        switch self {
        case .average:  return a + (b - a) / Float(sampleCount + 1)
        case .additive: return Swift.min(1, a + b)
        case .lighten:  return Swift.max(a, b)
        case .screen:   return 1 - (1 - a) * (1 - b)
        }
    }
}
