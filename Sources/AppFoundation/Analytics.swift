import Foundation

// MARK: - Event Model

/// A privacy-first analytics event. Never include PII in `name` or `parameters`.
public struct AnalyticsEvent: Sendable {
    /// Short snake_case name, e.g. `"onboarding_completed"`.
    public let name: String
    /// Optional scalar parameters (strings, numbers, booleans only).
    public let parameters: [String: AnalyticsValue]

    public init(_ name: String, _ parameters: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// A type-safe analytics parameter value.
public enum AnalyticsValue: Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public var description: String {
        switch self {
        case .string(let v): return v
        case .int(let v):    return "\(v)"
        case .double(let v): return "\(v)"
        case .bool(let v):   return "\(v)"
        }
    }
}

// MARK: - Protocol

/// Inject an `AnalyticsClient` into your app via the environment or a DI container.
/// The default implementation is a no-op so tests and previews never require a real backend.
public protocol AnalyticsClient: Sendable {
    /// Log a single analytics event.
    func log(_ event: AnalyticsEvent)
}

// MARK: - Implementations

/// No-op client — the default. Safe for tests and SwiftUI previews.
public struct NoOpAnalytics: AnalyticsClient {
    public init() {}
    public func log(_ event: AnalyticsEvent) {}
}

/// Prints events to the console. Use during development.
public struct ConsoleAnalytics: AnalyticsClient {
    public init() {}

    public func log(_ event: AnalyticsEvent) {
        if event.parameters.isEmpty {
            print("[Analytics] \(event.name)")
        } else {
            let pairs = event.parameters
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            print("[Analytics] \(event.name) { \(pairs) }")
        }
    }
}
