import Foundation

/// A single trade/quote sample: a `price` observed at a `time`.
public struct Tick: Equatable, Sendable {
    /// The observed price.
    public let price: Double
    /// When the price was observed.
    public let time: Date

    /// Create a tick.
    public init(price: Double, time: Date) {
        self.price = price
        self.time = time
    }
}

/// Aggregates a stream of ticks into OHLC ``Candle`` values for a fixed ``Timeframe``, updating the
/// most-recent (live) candle in place as new ticks arrive.
///
/// This type is **pure and deterministic** — it depends only on the ticks fed to it — which makes
/// it the heavily unit-tested core of ChartsKit. Buckets are UTC-epoch-aligned (see ``Timeframe``).
///
/// ```swift
/// var agg = TickToCandleAggregator(timeframe: .m1)
/// agg.add(price: 100, time: t0)        // opens candle 0
/// agg.add(price: 103, time: t0 + 30)   // updates candle 0 (high=103, close=103)
/// let openedNew = agg.add(price: 101, time: t0 + 61)  // true — opens candle 1
/// ```
///
/// ## Behaviour
/// - The first tick in a bucket sets `open = high = low = close = price`.
/// - Subsequent ticks in the same bucket raise `high`, lower `low`, and set `close`.
/// - A tick in a later bucket appends a new candle. Gaps are **not** back-filled with empty
///   candles; the next candle simply starts at its own bucket.
/// - A tick older than the current (last) bucket is ignored, so out-of-order late ticks can't
///   corrupt history. (Out-of-order ticks *within* the current bucket are still applied.)
public struct TickToCandleAggregator: Equatable, Sendable {
    /// The timeframe each candle aggregates.
    public let timeframe: Timeframe
    /// The candles built so far, oldest first. The last element is the live candle.
    public private(set) var candles: [Candle]

    /// The current live (most recent) candle, if any.
    public var latest: Candle? { candles.last }

    /// Create an aggregator for a timeframe, optionally seeded with existing candles.
    ///
    /// - Parameters:
    ///   - timeframe: The candle duration.
    ///   - candles: Pre-existing candles (oldest first). Default empty.
    public init(timeframe: Timeframe, candles: [Candle] = []) {
        self.timeframe = timeframe
        self.candles = candles
    }

    /// The UTC-epoch-aligned start of the bucket containing `time`.
    public func bucketStart(for time: Date) -> Date {
        let seconds = timeframe.seconds
        let floored = (time.timeIntervalSince1970 / seconds).rounded(.down) * seconds
        return Date(timeIntervalSince1970: floored)
    }

    /// Apply a tick.
    ///
    /// - Parameters:
    ///   - price: The observed price.
    ///   - time: When it was observed.
    /// - Returns: `true` if this tick opened a **new** candle, `false` if it updated the live one
    ///   (or was ignored as a stale, out-of-bucket tick).
    @discardableResult
    public mutating func add(price: Double, time: Date) -> Bool {
        let start = bucketStart(for: time)

        if let last = candles.last {
            if start < last.time {
                return false   // stale tick older than the current bucket — ignore
            }
            if start == last.time {
                var updated = last
                updated.high = max(updated.high, price)
                updated.low = min(updated.low, price)
                updated.close = price
                candles[candles.count - 1] = updated
                return false
            }
        }

        candles.append(Candle(time: start, open: price, high: price, low: price, close: price))
        return true
    }

    /// Apply a ``Tick``. See ``add(price:time:)``.
    @discardableResult
    public mutating func add(_ tick: Tick) -> Bool {
        add(price: tick.price, time: tick.time)
    }

    /// Apply a sequence of ticks in order.
    ///
    /// - Parameter ticks: Ticks to apply (should be roughly chronological).
    /// - Returns: The number of new candles opened.
    @discardableResult
    public mutating func add(_ ticks: [Tick]) -> Int {
        var opened = 0
        for tick in ticks where add(tick) { opened += 1 }
        return opened
    }

    /// Remove all candles.
    public mutating func reset() {
        candles.removeAll()
    }
}
