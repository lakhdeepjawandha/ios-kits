//
//  ChartShaders.metal
//  ChartsKit
//
//  A single, minimal coloured-triangle pipeline shared by every chart primitive. All chart
//  geometry — candle bodies, wicks, gridlines, the crosshair, line strips, and bars — is built on
//  the CPU (see `ChartGeometry`) as filled triangles in normalized device coordinates, so one
//  vertex+fragment pair can draw the entire scene in a single draw call.
//
//  This file ships as a resource and is compiled at runtime by `CandlestickRenderer` via
//  `device.makeLibrary(source:)`, matching RenderKit's approach.
//

#include <metal_stdlib>
using namespace metal;

// Memory layout matches `ChartVertex` in Swift: a packed float2 position (NDC) followed by a
// float4 RGBA colour (16-byte aligned → 32-byte stride).
struct ChartVertex {
    float2 position;
    float4 color;
};

struct ChartVOut {
    float4 position [[position]];
    float4 color;
};

/// **Chart vertex shader.** Indexes the colour-vertex buffer by `vertex_id` and passes position
/// (promoted to clip space) and colour straight through to the rasterizer.
vertex ChartVOut chart_vertex(constant ChartVertex* vertices [[buffer(0)]],
                              uint vid [[vertex_id]]) {
    ChartVOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.color = vertices[vid].color;
    return out;
}

/// **Chart fragment shader.** Emits the interpolated vertex colour. Alpha enables translucent
/// gridlines and crosshair over the candles via standard alpha blending.
fragment float4 chart_fragment(ChartVOut in [[stage_in]]) {
    return in.color;
}
