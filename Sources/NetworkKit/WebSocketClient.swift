import Foundation

/// Streams text/data frames from a WebSocket as an AsyncStream.
/// Used by the real-time watchlist (#47) and paper-trading (#48).
public final class WebSocketClient {
    private let url: URL
    private var task: URLSessionWebSocketTask?

    public init(url: URL) { self.url = url }

    public func connect() -> AsyncStream<String> {
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        return AsyncStream { continuation in
            func receive() {
                task.receive { result in
                    switch result {
                    case .success(.string(let text)):
                        continuation.yield(text)
                        receive()
                    case .success(.data(let data)):
                        if let text = String(data: data, encoding: .utf8) { continuation.yield(text) }
                        receive()
                    case .success:
                        receive()
                    case .failure:
                        continuation.finish()
                    }
                }
            }
            receive()
            continuation.onTermination = { _ in task.cancel(with: .goingAway, reason: nil) }
        }
    }

    public func disconnect() { task?.cancel(with: .goingAway, reason: nil) }
}
