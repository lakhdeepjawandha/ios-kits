import Foundation

/// Pure, on-device helpers that pull structured values — money amounts and dates — out of OCR'd
/// receipt and statement text.
///
/// This is the unit-tested core of VisionScanKit: it takes already-recognized strings (so it needs
/// no camera or Vision) and is fully deterministic. Amounts are parsed as `Decimal` to avoid binary
/// floating-point rounding; dates use `NSDataDetector`, which recognizes many natural formats
/// entirely on-device.
public enum ReceiptParser {

    // Monetary numbers: optional currency symbol, optional thousands separators, exactly 2 decimals.
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"[$£€]?\s?(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}"#)

    /// Every monetary amount found in the given lines, in reading order.
    ///
    /// Recognizes values like `12.34`, `$12.34`, and `1,234.56`. Values are returned as `Decimal`.
    ///
    /// - Parameter lines: Recognized text lines.
    /// - Returns: All amounts found, in order of appearance.
    public static func extractAmounts(from lines: [String]) -> [Decimal] {
        var amounts: [Decimal] = []
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in amountRegex.matches(in: line, range: range) {
                guard let matchRange = Range(match.range, in: line) else { continue }
                if let value = decimal(from: String(line[matchRange])) {
                    amounts.append(value)
                }
            }
        }
        return amounts
    }

    /// The most likely **total** amount.
    ///
    /// Prefers an amount on a line labelled "total" (ignoring "subtotal"); if several qualify, the
    /// largest is chosen. When no total label exists, falls back to the largest amount found.
    ///
    /// - Parameter lines: Recognized text lines.
    /// - Returns: The total, or `nil` if no amount is present.
    public static func extractTotal(from lines: [String]) -> Decimal? {
        var labeled: [Decimal] = []
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("total"), !lower.contains("subtotal") else { continue }
            if let last = extractAmounts(from: [line]).last {
                labeled.append(last)
            }
        }
        if let maxLabeled = labeled.max() { return maxLabeled }
        return extractAmounts(from: lines).max()
    }

    /// Every date found across the given lines, in reading order.
    ///
    /// Uses `NSDataDetector`, which understands formats like `01/15/2024`, `2024-03-22`,
    /// `March 22, 2024`, and `22 Mar 2024`.
    ///
    /// - Parameter lines: Recognized text lines.
    /// - Returns: All detected dates.
    public static func extractDates(from lines: [String]) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        var dates: [Date] = []
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in detector.matches(in: line, range: range) {
                if let date = match.date { dates.append(date) }
            }
        }
        return dates
    }

    /// The first date found across the lines, or `nil`.
    public static func extractFirstDate(from lines: [String]) -> Date? {
        extractDates(from: lines).first
    }

    // MARK: - Convenience over recognized text

    /// ``extractTotal(from:)`` over recognized-text observations.
    public static func extractTotal(from texts: [RecognizedText]) -> Decimal? {
        extractTotal(from: texts.map(\.string))
    }

    /// ``extractFirstDate(from:)`` over recognized-text observations.
    public static func extractFirstDate(from texts: [RecognizedText]) -> Date? {
        extractFirstDate(from: texts.map(\.string))
    }

    // MARK: - Internals

    /// Parse a matched money substring into a `Decimal`, stripping symbols, spaces, and separators.
    static func decimal(from raw: String) -> Decimal? {
        let cleaned = raw.filter { $0.isNumber || $0 == "." }
        return Decimal(string: cleaned)
    }
}
