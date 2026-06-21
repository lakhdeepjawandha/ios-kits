import Foundation

/// Delays execution of a closure until `interval` seconds have elapsed since the last call.
///
/// ```swift
/// let debouncer = Debouncer(interval: 0.3)
/// textField.onChange { text in
///     await debouncer.call { await viewModel.search(text) }
/// }
/// ```
public actor Debouncer {
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    /// Create a debouncer with the given delay interval in seconds.
    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Schedule `action` to run after `interval` seconds, cancelling any pending call.
    public func call(_ action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task { [interval] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    /// Cancel any pending scheduled action.
    public func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: -

/// Ensures `action` is called at most once per `interval` seconds.
///
/// Unlike `Debouncer`, the first call fires immediately; subsequent calls within the
/// window are ignored until the interval elapses.
///
/// ```swift
/// let throttler = Throttler(interval: 1.0)
/// scrollView.onScroll { offset in
///     await throttler.call { await viewModel.prefetch(at: offset) }
/// }
/// ```
public actor Throttler {
    private let interval: TimeInterval
    private var lastFired: Date = .distantPast

    /// Create a throttler with the given minimum interval between executions.
    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Call `action` immediately if the throttle window has elapsed, otherwise drop the call.
    public func call(_ action: @escaping @Sendable () async -> Void) async {
        let now = Date()
        guard now.timeIntervalSince(lastFired) >= interval else { return }
        lastFired = now
        await action()
    }
}
