import Foundation

/// "Nice number" axis tick generation (Heckbert's algorithm) for clean, human-friendly gridlines
/// and labels. Pure and unit-tested.
public enum AxisTicks {

    /// Evenly-spaced "nice" tick values within `[min, max]`.
    ///
    /// Tick spacing is chosen from the 1/2/5/10 family so labels read cleanly (e.g. 0, 20, 40, …
    /// rather than 0, 17.3, 34.6, …). Returned ticks are clamped to the `[min, max]` interval.
    ///
    /// - Parameters:
    ///   - min: Lower bound of the data range.
    ///   - max: Upper bound of the data range.
    ///   - count: Desired approximate number of ticks (the actual count is close, not exact).
    ///     Default `5`.
    /// - Returns: Sorted tick values, or `[]` if the range is empty/invalid.
    public static func ticks(min: Double, max: Double, count: Int = 5) -> [Double] {
        guard max > min, count >= 2 else { return [] }
        let range = niceNum(max - min, round: false)
        let step = niceNum(range / Double(count - 1), round: true)
        guard step > 0 else { return [] }

        let graphMin = (min / step).rounded(.down) * step
        let graphMax = (max / step).rounded(.up) * step

        var result: [Double] = []
        var value = graphMin
        // Guard against runaway loops from pathological inputs.
        let maxIterations = count * 10 + 10
        var iterations = 0
        while value <= graphMax + step * 0.5, iterations < maxIterations {
            // Snap values very close to zero to exactly zero for clean labels.
            let snapped = abs(value) < step * 1e-6 ? 0 : value
            if snapped >= min - step * 1e-6, snapped <= max + step * 1e-6 {
                result.append(snapped)
            }
            value += step
            iterations += 1
        }
        return result
    }

    /// Round a positive number to a "nice" value from the 1/2/5/10 family.
    ///
    /// - Parameters:
    ///   - value: A positive magnitude (e.g. a range or a candidate step).
    ///   - round: When `true`, round to the nearest nice number; when `false`, round up to the next
    ///     nice number (used to bracket a full range).
    /// - Returns: The nice number.
    public static func niceNum(_ value: Double, round: Bool) -> Double {
        guard value > 0 else { return 0 }
        let exponent = (log10(value)).rounded(.down)
        let fraction = value / pow(10, exponent)
        let niceFraction: Double
        if round {
            switch fraction {
            case ..<1.5: niceFraction = 1
            case ..<3:   niceFraction = 2
            case ..<7:   niceFraction = 5
            default:     niceFraction = 10
            }
        } else {
            switch fraction {
            case ...1: niceFraction = 1
            case ...2: niceFraction = 2
            case ...5: niceFraction = 5
            default:   niceFraction = 10
            }
        }
        return niceFraction * pow(10, exponent)
    }
}
