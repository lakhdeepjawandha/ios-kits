import Foundation

/// A candlestick timeframe — the duration each candle aggregates.
///
/// Buckets are aligned to UTC epoch boundaries (e.g. a `m5` candle covers `[…:00, …:05)`), which
/// keeps aggregation pure and deterministic regardless of the device's calendar or time zone.
public enum Timeframe: String, CaseIterable, Sendable, Identifiable {
    /// One minute.
    case m1
    /// Five minutes.
    case m5
    /// One hour.
    case h1
    /// One day (24h, UTC-aligned).
    case d1

    public var id: String { rawValue }

    /// The timeframe duration in seconds.
    public var seconds: TimeInterval {
        switch self {
        case .m1: return 60
        case .m5: return 300
        case .h1: return 3_600
        case .d1: return 86_400
        }
    }

    /// Short label for UI controls (e.g. a segmented picker): `"1m"`, `"5m"`, `"1h"`, `"1d"`.
    public var displayName: String {
        switch self {
        case .m1: return "1m"
        case .m5: return "5m"
        case .h1: return "1h"
        case .d1: return "1d"
        }
    }
}
