import Foundation

/// Minimal abstraction over a WebSocket task so ``WebSocketClient`` can be driven by a real
/// `URLSessionWebSocketTask` in production or a fake in tests.
public protocol WebSocketTask: AnyObject {
    /// Begin the connection.
    func resume()
    /// Tear the connection down.
    func cancel()
    /// Await the next inbound frame. Throws when the connection closes or fails.
    func receive() async throws -> URLSessionWebSocketTask.Message
    /// Send a keepalive ping and await its pong.
    func sendPing() async throws
}

/// Adapts a `URLSessionWebSocketTask` to ``WebSocketTask``.
final class URLSessionWebSocketTaskAdapter: WebSocketTask {
    private let task: URLSessionWebSocketTask
    init(task: URLSessionWebSocketTask) { self.task = task }

    func resume() { task.resume() }
    func cancel() { task.cancel(with: .goingAway, reason: nil) }
    func receive() async throws -> URLSessionWebSocketTask.Message { try await task.receive() }

    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

/// Policy governing automatic reconnection after a WebSocket drops.
public struct ReconnectPolicy: Sendable, Equatable {
    /// Maximum reconnect attempts after a drop. `0` disables reconnection.
    public var maxAttempts: Int
    /// Backoff schedule between reconnect attempts.
    public var backoff: Backoff

    /// Create a reconnect policy.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum reconnect attempts. Default `5`.
    ///   - backoff: Backoff between attempts. Default starts at 1s, doubling up to 30s.
    public init(maxAttempts: Int = 5, backoff: Backoff = Backoff(base: 1, multiplier: 2, max: 30)) {
        self.maxAttempts = maxAttempts
        self.backoff = backoff
    }

    /// Reconnect up to five times with exponential backoff.
    public static let `default` = ReconnectPolicy()
    /// Never reconnect; the stream finishes on the first drop.
    public static let none = ReconnectPolicy(maxAttempts: 0, backoff: Backoff(base: 0, multiplier: 1, max: 0))
}

/// Streams frames from a WebSocket as an `AsyncStream`, with automatic reconnect, exponential
/// backoff, and ping/pong keepalive.
///
/// Use ``connect()`` for raw text frames, or ``connect(decoding:decoder:)`` to decode each frame as
/// JSON into a typed model:
///
/// ```swift
/// let socket = WebSocketClient(url: URL(string: "wss://stream.example.com/ticks")!)
/// for await tick in socket.connect(decoding: Tick.self) {
///     update(tick)
/// }
/// ```
///
/// The stream survives transient drops: when the connection fails, the client waits per
/// ``ReconnectPolicy`` and reconnects, resetting the backoff after any successful frame. Once
/// reconnect attempts are exhausted the stream finishes. A successful read also keeps the
/// connection warm via periodic pings (``pingInterval``). Cancelling the consuming task (or calling
/// ``disconnect()``) tears everything down.
public final class WebSocketClient {
    private let url: URL
    private let reconnect: ReconnectPolicy
    private let pingInterval: TimeInterval
    private let taskFactory: @Sendable () -> WebSocketTask
    private let sleeper: Sleeper

    private let lock = NSLock()
    private var runLoop: Task<Void, Never>?
    private var currentTask: WebSocketTask?

    /// Create a WebSocket client against a live `URLSession` task.
    ///
    /// - Parameters:
    ///   - url: The `wss://`/`ws://` endpoint.
    ///   - reconnect: Reconnect behaviour after drops. Defaults to ``ReconnectPolicy/default``.
    ///   - pingInterval: Seconds between keepalive pings; `0` disables pings. Default `30`.
    public convenience init(url: URL,
                            reconnect: ReconnectPolicy = .default,
                            pingInterval: TimeInterval = 30) {
        self.init(url: url,
                  reconnect: reconnect,
                  pingInterval: pingInterval,
                  taskFactory: { URLSessionWebSocketTaskAdapter(task: URLSession.shared.webSocketTask(with: url)) },
                  sleeper: liveSleeper)
    }

    /// Designated initializer with an injectable task factory and sleeper, used by tests.
    init(url: URL,
         reconnect: ReconnectPolicy = .default,
         pingInterval: TimeInterval = 30,
         taskFactory: @escaping @Sendable () -> WebSocketTask,
         sleeper: @escaping Sleeper) {
        self.url = url
        self.reconnect = reconnect
        self.pingInterval = pingInterval
        self.taskFactory = taskFactory
        self.sleeper = sleeper
    }

    deinit { disconnect() }

    /// Stream inbound frames as `String`s (text frames, and data frames decoded as UTF-8).
    public func connect() -> AsyncStream<String> {
        stream { message in
            switch message {
            case let .string(text): return text
            case let .data(data): return String(data: data, encoding: .utf8)
            @unknown default: return nil
            }
        }
    }

    /// Stream inbound frames decoded as JSON into `T`.
    ///
    /// Frames that fail to decode are skipped (the connection stays open) so one malformed message
    /// does not end the stream.
    ///
    /// - Parameters:
    ///   - type: The model type to decode each frame into.
    ///   - decoder: Decoder to use. Defaults to a fresh `JSONDecoder`.
    /// - Returns: An `AsyncStream` of decoded values.
    public func connect<T: Decodable>(decoding type: T.Type,
                                      decoder: JSONDecoder = JSONDecoder()) -> AsyncStream<T> {
        stream { message in
            let data: Data?
            switch message {
            case let .string(text): data = Data(text.utf8)
            case let .data(payload): data = payload
            @unknown default: data = nil
            }
            guard let data else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    /// Stop streaming and tear down the underlying connection.
    public func disconnect() {
        lock.lock()
        let loop = runLoop
        let task = currentTask
        runLoop = nil
        currentTask = nil
        lock.unlock()
        loop?.cancel()
        task?.cancel()
    }

    // MARK: - Core

    /// Shared connect/receive/reconnect loop. `transform` maps a frame to a value to yield, or
    /// `nil` to skip it.
    private func stream<T>(transform: @escaping @Sendable (URLSessionWebSocketTask.Message) -> T?) -> AsyncStream<T> {
        AsyncStream { continuation in
            let loop = Task { [weak self] in
                await self?.run(transform: transform) { continuation.yield($0) }
                continuation.finish()
            }
            lock.lock(); runLoop = loop; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                loop.cancel()
                self?.cancelCurrentTask()
            }
        }
    }

    private func run<T>(transform: @escaping (URLSessionWebSocketTask.Message) -> T?,
                        yield: @escaping (T) -> Void) async {
        var attempt = 0
        while !Task.isCancelled {
            let task = taskFactory()
            setCurrentTask(task)
            task.resume()
            let pinger = startPing(on: task)

            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    attempt = 0   // a successful read resets the backoff
                    if let value = transform(message) { yield(value) }
                }
                pinger.cancel()
                task.cancel()
            } catch {
                pinger.cancel()
                task.cancel()
                if Task.isCancelled { break }
                guard attempt < reconnect.maxAttempts else { break }
                let delay = reconnect.backoff.delay(forAttempt: attempt)
                attempt += 1
                do { try await sleeper(delay) } catch { break }
            }
        }
        clearCurrentTask()
    }

    private func startPing(on task: WebSocketTask) -> Task<Void, Never> {
        let interval = pingInterval
        guard interval > 0 else { return Task {} }
        let sleeper = self.sleeper
        return Task {
            while !Task.isCancelled {
                do { try await sleeper(interval) } catch { return }
                if Task.isCancelled { return }
                try? await task.sendPing()
            }
        }
    }

    // MARK: - Thread-safe task storage

    private func setCurrentTask(_ task: WebSocketTask) {
        lock.lock(); currentTask = task; lock.unlock()
    }

    private func clearCurrentTask() {
        lock.lock(); currentTask = nil; lock.unlock()
    }

    private func cancelCurrentTask() {
        lock.lock(); let task = currentTask; currentTask = nil; lock.unlock()
        task?.cancel()
    }
}
