import CoreGraphics
import Foundation

/// Pure mapping between chart data space (candle **index** + **price**) and screen space (pixels),
/// with pan and zoom. This is the geometry core of the charts and is fully unit-tested.
///
/// - **X axis**: candle index. ``panIndex`` is the fractional index at the left edge (`x = 0`);
///   ``visibleCandles`` is how many candles span the plot width (the zoom level).
/// - **Y axis**: price. ``priceMax`` maps to the top (`y = 0`) and ``priceMin`` to the bottom,
///   matching UIKit's top-left origin.
///
/// All conversions are exact inverses of one another (within floating-point error), which the tests
/// assert via round-trips.
public struct ChartScale: Equatable, Sendable {
    /// Plot area size in points.
    public var plotSize: CGSize
    /// Number of candles spanning the plot width (zoom). Always `>= minVisibleCandles`.
    public var visibleCandles: Double
    /// Fractional candle index at the left edge of the plot (pan position).
    public var panIndex: Double
    /// Lowest price shown (maps to the bottom edge).
    public var priceMin: Double
    /// Highest price shown (maps to the top edge).
    public var priceMax: Double
    /// Smallest allowed ``visibleCandles`` (max zoom-in).
    public var minVisibleCandles: Double
    /// Largest allowed ``visibleCandles`` (max zoom-out).
    public var maxVisibleCandles: Double

    /// Create a scale.
    ///
    /// - Parameters:
    ///   - plotSize: Plot size in points.
    ///   - visibleCandles: Candles across the width (zoom). Clamped to the limits below.
    ///   - panIndex: Fractional index at the left edge.
    ///   - priceMin: Lowest price (bottom).
    ///   - priceMax: Highest price (top).
    ///   - minVisibleCandles: Minimum zoom span. Default `3`.
    ///   - maxVisibleCandles: Maximum zoom span. Default `10000`.
    public init(plotSize: CGSize,
                visibleCandles: Double,
                panIndex: Double,
                priceMin: Double,
                priceMax: Double,
                minVisibleCandles: Double = 3,
                maxVisibleCandles: Double = 10_000) {
        self.plotSize = plotSize
        self.minVisibleCandles = minVisibleCandles
        self.maxVisibleCandles = maxVisibleCandles
        self.visibleCandles = visibleCandles.clamped(to: minVisibleCandles...maxVisibleCandles)
        self.panIndex = panIndex
        self.priceMin = priceMin
        self.priceMax = priceMax
    }

    /// Width in points allotted to each candle (including its gap).
    public var candleWidth: CGFloat {
        guard visibleCandles > 0 else { return 0 }
        return plotSize.width / CGFloat(visibleCandles)
    }

    private var priceSpan: Double { priceMax - priceMin }

    // MARK: - X (index <-> screen)

    /// Screen x (points) of the **centre** of the candle at `index`.
    public func x(forIndex index: Double) -> CGFloat {
        CGFloat(index - panIndex + 0.5) * candleWidth
    }

    /// Fractional candle index under screen x (points). Inverse of ``x(forIndex:)``.
    public func index(forX x: CGFloat) -> Double {
        guard candleWidth > 0 else { return panIndex }
        return Double(x / candleWidth) + panIndex - 0.5
    }

    // MARK: - Y (price <-> screen)

    /// Screen y (points) for a price. `priceMax` → `0` (top), `priceMin` → height (bottom).
    public func y(forPrice price: Double) -> CGFloat {
        guard priceSpan > 0 else { return plotSize.height / 2 }
        let t = (priceMax - price) / priceSpan
        return CGFloat(t) * plotSize.height
    }

    /// Price at screen y (points). Inverse of ``y(forPrice:)``.
    public func price(forY y: CGFloat) -> Double {
        guard plotSize.height > 0 else { return priceMax }
        let t = Double(y / plotSize.height)
        return priceMax - t * priceSpan
    }

    // MARK: - Pan & zoom

    /// A copy panned horizontally by a pixel delta. Dragging content right (positive `dx`) reveals
    /// **earlier** candles, decreasing ``panIndex``.
    public func panned(byPixels dx: CGFloat) -> ChartScale {
        guard candleWidth > 0 else { return self }
        var copy = self
        copy.panIndex = panIndex - Double(dx / candleWidth)
        return copy
    }

    /// A copy zoomed about an anchor x, keeping the candle under `anchorX` fixed on screen.
    ///
    /// - Parameters:
    ///   - factor: Zoom factor (`> 1` zooms in / shows fewer candles; `< 1` zooms out). A pinch
    ///     gesture's `scale` maps directly to this.
    ///   - anchorX: The screen x (points) to pivot around (e.g. the pinch midpoint).
    public func zoomed(factor: CGFloat, anchorX: CGFloat) -> ChartScale {
        guard factor > 0, candleWidth > 0 else { return self }
        let anchorIndex = index(forX: anchorX)
        var copy = self
        copy.visibleCandles = (visibleCandles / Double(factor)).clamped(to: minVisibleCandles...maxVisibleCandles)
        // Keep the anchored candle under the same pixel: anchorX = (anchorIndex - panIndex + 0.5) * newWidth
        if copy.candleWidth > 0 {
            copy.panIndex = anchorIndex + 0.5 - Double(anchorX / copy.candleWidth)
        }
        return copy
    }

    // MARK: - Auto price range

    /// The min/max price across a slice of candles, expanded by a padding fraction.
    ///
    /// - Parameters:
    ///   - candles: Candles to measure (typically the visible slice).
    ///   - padding: Fraction of the price span to add above and below. Default `0.05` (5%).
    /// - Returns: `(min, max)`, or `nil` if `candles` is empty. When all prices are equal the range
    ///   is widened to a small non-zero band so division stays well-defined.
    public static func priceRange<S: Sequence>(for candles: S, padding: Double = 0.05) -> (min: Double, max: Double)?
        where S.Element == Candle {
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        var found = false
        for candle in candles {
            found = true
            lo = Swift.min(lo, candle.low)
            hi = Swift.max(hi, candle.high)
        }
        guard found else { return nil }
        if hi <= lo {
            let bump = abs(hi) * 0.01 + 0.5
            return (lo - bump, hi + bump)
        }
        let pad = (hi - lo) * padding
        return (lo - pad, hi + pad)
    }
}

extension Comparable {
    /// Clamp to a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
