import Foundation

/// Exponential backoff schedule shared by request retries and WebSocket reconnects.
///
/// The delay for a zero-based `attempt` is `base * multiplier^attempt`, capped at `max`:
///
/// ```
/// attempt 0 → base
/// attempt 1 → base * multiplier
/// attempt 2 → base * multiplier²   (clamped to max)
/// ```
public struct Backoff: Sendable, Equatable {
    /// Delay before the first retry, in seconds.
    public var base: TimeInterval
    /// Growth factor applied per attempt.
    public var multiplier: Double
    /// Upper bound on any single delay, in seconds.
    public var max: TimeInterval

    /// Create a backoff schedule.
    ///
    /// - Parameters:
    ///   - base: Delay before the first retry. Default `0.5`.
    ///   - multiplier: Growth factor per attempt. Default `2.0`.
    ///   - max: Maximum single delay. Default `30`.
    public init(base: TimeInterval = 0.5, multiplier: Double = 2.0, max: TimeInterval = 30) {
        self.base = base
        self.multiplier = multiplier
        self.max = max
    }

    /// The delay to wait before the given zero-based `attempt`.
    ///
    /// - Parameter attempt: Zero-based retry index (`0` is the first retry).
    /// - Returns: Seconds to wait, never below `0` and never above ``max``.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return 0 }
        let raw = base * pow(multiplier, Double(attempt))
        return Swift.min(Swift.max(0, raw), max)
    }
}

/// Policy governing whether and how a failed ``APIClient/send(_:)`` request is retried.
///
/// A request is retried while the attempt count is below ``maxRetries`` **and** ``isRetryable``
/// returns `true` for the error. The wait between attempts follows ``backoff``.
///
/// The default ``isRetryable`` retries transient failures only: transport errors, HTTP `429`
/// (Too Many Requests), and `5xx` server errors. Client errors like `400`/`401`/`404` are not
/// retried because repeating them cannot succeed.
public struct RetryPolicy: Sendable {
    /// Maximum number of retries after the initial attempt. `0` disables retrying.
    public var maxRetries: Int
    /// Backoff schedule controlling the wait between attempts.
    public var backoff: Backoff
    /// Predicate deciding whether a given error should be retried.
    public var isRetryable: @Sendable (APIError) -> Bool

    /// Create a retry policy.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum retries after the first attempt. Default `2`.
    ///   - backoff: Backoff schedule. Default ``Backoff/init(base:multiplier:max:)``.
    ///   - isRetryable: Predicate for retryable errors. Defaults to ``defaultIsRetryable``.
    public init(maxRetries: Int = 2,
                backoff: Backoff = Backoff(),
                isRetryable: @escaping @Sendable (APIError) -> Bool = RetryPolicy.defaultIsRetryable) {
        self.maxRetries = maxRetries
        self.backoff = backoff
        self.isRetryable = isRetryable
    }

    /// Delay before the given zero-based retry attempt, per ``backoff``.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        backoff.delay(forAttempt: attempt)
    }

    /// Retries transport failures, HTTP `429`, and `5xx` responses; never client (`4xx`) errors.
    public static let defaultIsRetryable: @Sendable (APIError) -> Bool = { error in
        switch error {
        case .transport:
            return true
        case let .unacceptableStatus(code, _):
            return code == 429 || (500..<600).contains(code)
        default:
            return false
        }
    }

    /// A policy that performs no retries.
    public static let none = RetryPolicy(maxRetries: 0)

    /// A sensible default: two retries with exponential backoff on transient failures.
    public static let `default` = RetryPolicy()
}

/// Suspends the current task for the given number of seconds. Injectable so tests can run the
/// retry/reconnect logic without real waiting.
typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

/// Default ``Sleeper`` backed by `Task.sleep`. Skips sleeping for non-positive durations.
let liveSleeper: Sleeper = { seconds in
    guard seconds > 0 else { return }
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}
