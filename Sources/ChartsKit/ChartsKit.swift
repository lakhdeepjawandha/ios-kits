import Foundation

/// Metal-accelerated charts (candlestick / line / bar) used by trading & finance apps.
/// First implementation target: #47 PulseChart candlestick MTKView.
public enum ChartsKit {
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
