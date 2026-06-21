//
//  Shaders.metal
//  RenderKit
//
//  All RenderKit fragment shaders, plus the shared full-screen-triangle vertex shader. This file
//  ships as a *resource* and is compiled at runtime by `MetalContext` via
//  `device.makeLibrary(source:)`, so it does not depend on the build system's Metal toolchain.
//
//  Every shader samples its input with a normalized, clamp-to-edge linear sampler and operates in
//  the texture's stored colour space (textures are loaded with sRGB decoding disabled, so values
//  are treated as plain 0...1). The CPU-side reference math lives in `ColorMath.swift` and is kept
//  byte-for-byte equivalent so the headless unit tests validate the same formulas.
//

#include <metal_stdlib>
using namespace metal;

// Interpolated output of the full-screen vertex stage.
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Uniforms for the colour-adjustment shader. Layout matches `ColorAdjustUniforms` in Swift
// (three tightly-packed 32-bit floats).
struct ColorAdjustUniforms {
    float brightness;
    float contrast;
    float saturation;
};

constant float3 kRec709 = float3(0.2126, 0.7152, 0.0722);

/// **Full-screen triangle vertex shader.**
///
/// Emits a single oversized triangle that covers the whole viewport from `vertex_id` alone — no
/// vertex or index buffers required. UVs are derived from clip-space position with a vertical flip
/// so that `uv = (0,0)` is the top-left of the sampled texture.
vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 p = positions[vid];
    VertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = float2((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5);
    return out;
}

/// **Texture passthrough.** Samples and returns the source colour unchanged — the baseline pass and
/// a useful identity step in a filter chain.
fragment float4 passthrough_fragment(VertexOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    return src.sample(s, in.uv);
}

/// **Brightness / contrast / saturation.**
///
/// Applies, in order: brightness (scale about black), contrast (scale about mid-grey `0.5`), and
/// saturation (interpolate between Rec. 709 luminance-grey and full colour). Alpha is preserved and
/// RGB is clamped to `0...1`. Each parameter has an identity of `1`.
fragment float4 color_adjust_fragment(VertexOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      constant ColorAdjustUniforms& u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 c = src.sample(s, in.uv);
    float3 rgb = c.rgb * u.brightness;
    rgb = (rgb - 0.5) * u.contrast + 0.5;
    float lum = dot(rgb, kRec709);
    rgb = mix(float3(lum), rgb, u.saturation);
    return float4(clamp(rgb, 0.0, 1.0), c.a);
}

/// **Separable Gaussian blur (one axis per invocation).**
///
/// Reads a one-sided, pre-normalized weight array (`weights[0]` is the centre tap) and samples
/// `±radius` taps along `offset` (which encodes both the texel size and the blur direction). Run it
/// twice — horizontally then vertically — for a full 2-D Gaussian. Because the weights are
/// normalized, blurring a flat colour returns that colour unchanged.
fragment float4 gaussian_blur_fragment(VertexOut in [[stage_in]],
                                       texture2d<float> src [[texture(0)]],
                                       constant float* weights [[buffer(0)]],
                                       constant int& radius [[buffer(1)]],
                                       constant float2& offset [[buffer(2)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 sum = src.sample(s, in.uv) * weights[0];
    for (int i = 1; i <= radius; ++i) {
        float2 d = offset * float(i);
        sum += src.sample(s, in.uv + d) * weights[i];
        sum += src.sample(s, in.uv - d) * weights[i];
    }
    return sum;
}

/// **Unsharp-mask sharpen.**
///
/// Combines the original image with a pre-computed blurred copy: `out = in + amount·(in − blur)`.
/// This boosts local contrast (edges) while leaving flat regions untouched, which is the standard
/// unsharp-masking technique. Alpha is taken from the original; RGB is clamped to `0...1`.
fragment float4 unsharp_fragment(VertexOut in [[stage_in]],
                                 texture2d<float> original [[texture(0)]],
                                 texture2d<float> blurred [[texture(1)]],
                                 constant float& amount [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 o = original.sample(s, in.uv);
    float4 b = blurred.sample(s, in.uv);
    float3 rgb = o.rgb + amount * (o.rgb - b.rgb);
    return float4(clamp(rgb, 0.0, 1.0), o.a);
}

/// **Frame compositor.**
///
/// Blends an `incoming` frame into the running `accumulator` using one of four modes, matching
/// `BlendMode` in Swift:
/// - `0` average — incremental arithmetic mean using `count` (frames already accumulated);
/// - `1` additive — `min(a + b, 1)`;
/// - `2` lighten — `max(a, b)`;
/// - `3` screen — `1 − (1−a)(1−b)`.
///
/// Output alpha is forced to `1`. Starting from a zero-cleared accumulator, the first frame
/// (`count == 0`) passes through unchanged in every mode.
fragment float4 composite_fragment(VertexOut in [[stage_in]],
                                   texture2d<float> accum [[texture(0)]],
                                   texture2d<float> incoming [[texture(1)]],
                                   constant int& mode [[buffer(0)]],
                                   constant int& count [[buffer(1)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 a = accum.sample(s, in.uv);
    float4 b = incoming.sample(s, in.uv);
    float4 r;
    if (mode == 0) {
        r = a + (b - a) / float(count + 1);
    } else if (mode == 1) {
        r = min(a + b, 1.0);
    } else if (mode == 2) {
        r = max(a, b);
    } else {
        r = 1.0 - (1.0 - a) * (1.0 - b);
    }
    r.a = 1.0;
    return r;
}
