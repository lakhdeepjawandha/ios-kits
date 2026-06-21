import Foundation

/// Metal-accelerated charts (candlestick / line / bar) used by trading & finance apps.
///
/// ## Topics
/// ### Data
/// - ``Candle``
/// - ``Tick``
/// - ``Timeframe``
/// - ``TickToCandleAggregator``
/// ### Geometry & scaling
/// - ``ChartScale``
/// - ``AxisTicks``
/// - ``ChartGeometry``
/// - ``ChartVertex``
/// ### Rendering
/// - ``CandlestickRenderer``
/// - ``CandlestickChartView``
/// - ``LineChartView``
/// - ``BarChartView``
public enum ChartsKit {
    /// Short description of the module.
    public static let info = "Metal candlestick/line/bar charts."
}

/// A single OHLC candle. The tick->candle aggregator and renderer build on this.
public struct Candle: Equatable, Sendable {
    public let time: Date
    public var open, high, low, close: Double
    public init(time: Date, open: Double, high: Double, low: Double, close: Double) {
        self.time = time; self.open = open; self.high = high; self.low = low; self.close = close
    }
}

public extension Candle {
    /// A deterministic mock candle series for previews and tests (seeded random walk).
    ///
    /// The sequence depends only on its inputs, so previews and snapshot tests are stable.
    ///
    /// - Parameters:
    ///   - count: Number of candles.
    ///   - start: Time of the first candle. Default the UNIX epoch.
    ///   - interval: Seconds between candles. Default `60`.
    ///   - startPrice: Opening price of the first candle. Default `100`.
    ///   - seed: PRNG seed. Default `42`.
    /// - Returns: `count` candles, oldest first.
    static func mockSeries(count: Int,
                           start: Date = Date(timeIntervalSince1970: 0),
                           interval: TimeInterval = 60,
                           startPrice: Double = 100,
                           seed: UInt64 = 42) -> [Candle] {
        guard count > 0 else { return [] }
        var state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)   // [0, 1)
        }

        var candles: [Candle] = []
        var price = startPrice
        for i in 0..<count {
            let open = price
            let drift = (next() - 0.5) * 2          // [-1, 1)
            let close = max(1, open + drift * (open * 0.01))
            let wick = open * 0.005 * (1 + next())
            let high = max(open, close) + wick * next()
            let low = min(open, close) - wick * next()
            candles.append(Candle(time: start.addingTimeInterval(interval * Double(i)),
                                  open: open, high: high, low: low, close: close))
            price = close
        }
        return candles
    }
}
