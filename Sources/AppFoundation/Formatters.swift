import Foundation

// MARK: - Currency

public extension NumberFormatter {
    /// Cached AUD currency formatter, e.g. `$1,234.56`.
    static let aud: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "AUD"
        f.locale = Locale(identifier: "en_AU")
        return f
    }()

    /// Cached percentage formatter, e.g. `42%`.
    static let percent: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 0
        return f
    }()

    /// Cached compact number formatter, e.g. `1.2K`, `3.4M`.
    static let compact: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        // `compactDecimal` via FormatStyle is preferred on iOS 15+; this falls back gracefully.
        return f
    }()
}

// MARK: - Relative date

public extension RelativeDateTimeFormatter {
    /// Cached relative-date formatter, e.g. `"2 hours ago"`.
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

// MARK: - FormatStyle convenience extensions

public extension Double {
    /// Format as AUD currency string using the system locale, e.g. `(12.5).audString == "$12.50"`.
    var audString: String {
        NumberFormatter.aud.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Format as percentage string, e.g. `(0.42).percentString == "42%"`.
    var percentString: String {
        NumberFormatter.percent.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Format as compact string, e.g. `(1_200.0).compactString == "1,200"`.
    ///
    /// For true compact notation (`1.2K`) prefer `formatted(.number.notation(.compactName))`.
    var compactString: String {
        NumberFormatter.compact.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

public extension Date {
    /// Relative string from now, e.g. `"2 hours ago"`.
    var relativeString: String {
        RelativeDateTimeFormatter.relative.localizedString(for: self, relativeTo: Date())
    }
}
