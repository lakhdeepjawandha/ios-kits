import CoreGraphics
import simd

/// A coloured vertex in normalized device coordinates (NDC), matching `ChartVertex` in
/// `ChartShaders.metal` (a packed `float2` position followed by a `float4` colour).
public struct ChartVertex: Equatable {
    /// Clip-space position (`-1...1`, origin centre, +y up).
    public var position: SIMD2<Float>
    /// RGBA colour.
    public var color: SIMD4<Float>

    /// Create a vertex.
    public init(position: SIMD2<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}

/// An RGBA colour for chart geometry, kept Metal-free so geometry building is testable headless.
public struct ChartColor: Equatable, Sendable {
    public var r, g, b, a: Float
    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    var simd: SIMD4<Float> { SIMD4(r, g, b, a) }

    /// Bullish green.
    public static let bullish = ChartColor(0.20, 0.78, 0.35)
    /// Bearish red.
    public static let bearish = ChartColor(0.91, 0.22, 0.21)
    /// Faint gridline grey.
    public static let grid = ChartColor(0.5, 0.5, 0.5, 0.25)
    /// Crosshair grey.
    public static let crosshair = ChartColor(0.6, 0.6, 0.6, 0.8)
    /// Neutral line/bar blue.
    public static let line = ChartColor(0.20, 0.50, 0.95)
}

/// Pure builders that turn chart data + a ``ChartScale`` into triangle vertices in NDC.
///
/// Everything here is GPU-free: it returns `[ChartVertex]` arrays that ``CandlestickRenderer``
/// uploads and draws. Lines and rectangles are emitted as filled triangles (two per rectangle,
/// six vertices), so a single pipeline can draw bodies, wicks, gridlines, and the crosshair.
public enum ChartGeometry {

    /// Convert a screen-space point (points, top-left origin) to NDC for `size`.
    public static func ndc(_ point: CGPoint, in size: CGSize) -> SIMD2<Float> {
        guard size.width > 0, size.height > 0 else { return SIMD2(0, 0) }
        return SIMD2(Float(2 * point.x / size.width - 1),
                     Float(1 - 2 * point.y / size.height))
    }

    /// Append an axis-aligned rectangle (as two triangles, 6 vertices) given its top-left corner
    /// and size in screen points.
    public static func appendRect(_ vertices: inout [ChartVertex],
                                  x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                                  color: SIMD4<Float>, in size: CGSize) {
        let topLeft = ndc(CGPoint(x: x, y: y), in: size)
        let topRight = ndc(CGPoint(x: x + width, y: y), in: size)
        let bottomLeft = ndc(CGPoint(x: x, y: y + height), in: size)
        let bottomRight = ndc(CGPoint(x: x + width, y: y + height), in: size)
        vertices.append(ChartVertex(position: topLeft, color: color))
        vertices.append(ChartVertex(position: bottomLeft, color: color))
        vertices.append(ChartVertex(position: bottomRight, color: color))
        vertices.append(ChartVertex(position: topLeft, color: color))
        vertices.append(ChartVertex(position: bottomRight, color: color))
        vertices.append(ChartVertex(position: topRight, color: color))
    }

    /// The inclusive range of candle indices that intersect the visible plot (with a one-candle
    /// margin), or `nil` if none are visible.
    public static func visibleIndexRange(candleCount: Int, scale: ChartScale) -> ClosedRange<Int>? {
        guard candleCount > 0 else { return nil }
        let lo = max(0, Int(scale.panIndex.rounded(.down)) - 1)
        let hi = min(candleCount - 1, Int((scale.panIndex + scale.visibleCandles).rounded(.up)) + 1)
        guard lo <= hi else { return nil }
        return lo...hi
    }

    /// Vertices for candle bodies and wicks. Each visible candle contributes 12 vertices
    /// (6 body + 6 wick); bullish candles (`close >= open`) use `bullish`, others `bearish`.
    ///
    /// - Parameters:
    ///   - candles: All candles (absolute index space).
    ///   - scale: The active scale.
    ///   - bullish: Colour for up candles.
    ///   - bearish: Colour for down candles.
    ///   - bodyWidthFraction: Body width as a fraction of the candle slot. Default `0.7`.
    ///   - wickWidth: Wick width in points. Default `1.5`.
    public static func candleVertices(candles: [Candle],
                                      scale: ChartScale,
                                      bullish: ChartColor = .bullish,
                                      bearish: ChartColor = .bearish,
                                      bodyWidthFraction: CGFloat = 0.7,
                                      wickWidth: CGFloat = 1.5) -> [ChartVertex] {
        guard let range = visibleIndexRange(candleCount: candles.count, scale: scale) else { return [] }
        let size = scale.plotSize
        let slot = scale.candleWidth
        let bodyW = max(1, slot * bodyWidthFraction)
        var vertices: [ChartVertex] = []
        vertices.reserveCapacity(range.count * 12)

        for i in range {
            let candle = candles[i]
            let center = scale.x(forIndex: Double(i))
            let color = (candle.close >= candle.open ? bullish : bearish).simd

            // Wick: high → low.
            let yHigh = scale.y(forPrice: candle.high)
            let yLow = scale.y(forPrice: candle.low)
            appendRect(&vertices,
                       x: center - wickWidth / 2, y: yHigh,
                       width: wickWidth, height: max(1, yLow - yHigh),
                       color: color, in: size)

            // Body: open ↔ close.
            let yOpen = scale.y(forPrice: candle.open)
            let yClose = scale.y(forPrice: candle.close)
            let top = min(yOpen, yClose)
            let bottom = max(yOpen, yClose)
            appendRect(&vertices,
                       x: center - bodyW / 2, y: top,
                       width: bodyW, height: max(1, bottom - top),
                       color: color, in: size)
        }
        return vertices
    }

    /// Horizontal gridline vertices at the given price levels (6 vertices per line).
    public static func gridVertices(priceLevels: [Double],
                                    scale: ChartScale,
                                    color: ChartColor = .grid,
                                    thickness: CGFloat = 1) -> [ChartVertex] {
        let size = scale.plotSize
        var vertices: [ChartVertex] = []
        for price in priceLevels {
            let y = scale.y(forPrice: price)
            appendRect(&vertices, x: 0, y: y - thickness / 2, width: size.width, height: thickness,
                       color: color.simd, in: size)
        }
        return vertices
    }

    /// Crosshair vertices (a vertical and a horizontal line through `point`, 12 vertices total).
    public static func crosshairVertices(at point: CGPoint,
                                         scale: ChartScale,
                                         color: ChartColor = .crosshair,
                                         thickness: CGFloat = 1) -> [ChartVertex] {
        let size = scale.plotSize
        var vertices: [ChartVertex] = []
        appendRect(&vertices, x: point.x - thickness / 2, y: 0, width: thickness, height: size.height,
                   color: color.simd, in: size)
        appendRect(&vertices, x: 0, y: point.y - thickness / 2, width: size.width, height: thickness,
                   color: color.simd, in: size)
        return vertices
    }

    /// Vertices for a poly-line through `points` (screen points), as oriented thick segments
    /// (6 vertices per segment, so `6 * (points.count - 1)` total).
    public static func lineStripVertices(points: [CGPoint],
                                         in size: CGSize,
                                         color: ChartColor = .line,
                                         thickness: CGFloat = 2) -> [ChartVertex] {
        guard points.count >= 2 else { return [] }
        var vertices: [ChartVertex] = []
        let half = thickness / 2
        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
            // Unit normal, scaled to half-thickness.
            let nx = -dy / length * half
            let ny = dx / length * half
            let a = ndc(CGPoint(x: p0.x + nx, y: p0.y + ny), in: size)
            let b = ndc(CGPoint(x: p0.x - nx, y: p0.y - ny), in: size)
            let c = ndc(CGPoint(x: p1.x + nx, y: p1.y + ny), in: size)
            let d = ndc(CGPoint(x: p1.x - nx, y: p1.y - ny), in: size)
            let col = color.simd
            vertices.append(ChartVertex(position: a, color: col))
            vertices.append(ChartVertex(position: b, color: col))
            vertices.append(ChartVertex(position: c, color: col))
            vertices.append(ChartVertex(position: b, color: col))
            vertices.append(ChartVertex(position: d, color: col))
            vertices.append(ChartVertex(position: c, color: col))
        }
        return vertices
    }

    /// Vertices for vertical bars from a baseline price up to each value (6 vertices per bar).
    ///
    /// - Parameters:
    ///   - values: One value per candle index (absolute index space).
    ///   - scale: The active scale.
    ///   - baseline: The price the bars grow from. Default `0`.
    ///   - color: Bar colour.
    ///   - widthFraction: Bar width as a fraction of the candle slot. Default `0.6`.
    public static func barVertices(values: [Double],
                                   scale: ChartScale,
                                   baseline: Double = 0,
                                   color: ChartColor = .line,
                                   widthFraction: CGFloat = 0.6) -> [ChartVertex] {
        guard let range = visibleIndexRange(candleCount: values.count, scale: scale) else { return [] }
        let size = scale.plotSize
        let barW = max(1, scale.candleWidth * widthFraction)
        var vertices: [ChartVertex] = []
        let yBase = scale.y(forPrice: baseline)
        for i in range {
            let center = scale.x(forIndex: Double(i))
            let yValue = scale.y(forPrice: values[i])
            let top = min(yBase, yValue)
            let bottom = max(yBase, yValue)
            appendRect(&vertices, x: center - barW / 2, y: top, width: barW, height: max(1, bottom - top),
                       color: color.simd, in: size)
        }
        return vertices
    }
}
