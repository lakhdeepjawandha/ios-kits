import XCTest
@testable import NetworkKit

// MARK: - Test fixtures & helpers

private struct Quote: Codable, Equatable {
    let symbol: String
    let price: Double
    let currency: String
}

private struct Tick: Codable, Equatable {
    let symbol: String
    let price: Double
}

/// Thread-safe call counter usable from the synchronous `StubURLProtocol` handler.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    @discardableResult func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Records the delays requested of an injected sleeper without actually sleeping.
private actor SleepRecorder {
    private(set) var delays: [TimeInterval] = []
    func record(_ delay: TimeInterval) { delays.append(delay) }
}

private func quoteJSON() -> Data {
    Data(#"{"symbol":"BTC","price":42.5,"currency":"AUD"}"#.utf8)
}

// MARK: - Request building

final class RequestTests: XCTestCase {

    func testRelativePathJoinsBaseURLWithQuery() throws {
        let base = URL(string: "https://api.example.com")!
        let request = Request.get("v1/quotes")
            .adding(query: "symbol", "BTC")
            .adding(query: "currency", "AUD")
        let urlRequest = try request.urlRequest(baseURL: base)

        XCTAssertEqual(urlRequest.httpMethod, "GET")
        XCTAssertEqual(urlRequest.url?.absoluteString,
                       "https://api.example.com/v1/quotes?symbol=BTC&currency=AUD")
    }

    func testLeadingSlashPathDoesNotDoubleUp() throws {
        let base = URL(string: "https://api.example.com")!
        let urlRequest = try Request.get("/v1/quotes").urlRequest(baseURL: base)
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.example.com/v1/quotes")
    }

    func testAbsolutePathIgnoresBaseURL() throws {
        let base = URL(string: "https://api.example.com")!
        let urlRequest = try Request.get("https://other.example.com/data").urlRequest(baseURL: base)
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://other.example.com/data")
    }

    func testJSONBodySetsContentTypeAndBytes() throws {
        let tick = Tick(symbol: "ETH", price: 3.14)
        let request = try Request.post("v1/orders").jsonBody(tick)
        let urlRequest = try request.urlRequest(baseURL: URL(string: "https://api.example.com")!)

        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let decoded = try JSONDecoder().decode(Tick.self, from: XCTUnwrap(urlRequest.httpBody))
        XCTAssertEqual(decoded, tick)
    }

    func testHeaderBuilderSetsField() throws {
        let request = Request.get("v1/quotes").setting(header: "Accept", to: "application/json")
        let urlRequest = try request.urlRequest(baseURL: URL(string: "https://api.example.com")!)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Accept"), "application/json")
    }
}

// MARK: - Backoff & retry policy (pure logic)

final class BackoffTests: XCTestCase {

    func testExponentialGrowth() {
        let backoff = Backoff(base: 1, multiplier: 2, max: 100)
        XCTAssertEqual(backoff.delay(forAttempt: 0), 1)
        XCTAssertEqual(backoff.delay(forAttempt: 1), 2)
        XCTAssertEqual(backoff.delay(forAttempt: 2), 4)
        XCTAssertEqual(backoff.delay(forAttempt: 3), 8)
    }

    func testCappedAtMax() {
        let backoff = Backoff(base: 1, multiplier: 10, max: 5)
        XCTAssertEqual(backoff.delay(forAttempt: 5), 5)
    }

    func testDefaultIsRetryable() {
        let retryable = RetryPolicy.defaultIsRetryable
        XCTAssertTrue(retryable(.transport(URLError(.timedOut))))
        XCTAssertTrue(retryable(.unacceptableStatus(code: 500, body: nil)))
        XCTAssertTrue(retryable(.unacceptableStatus(code: 503, body: nil)))
        XCTAssertTrue(retryable(.unacceptableStatus(code: 429, body: nil)))
        XCTAssertFalse(retryable(.unacceptableStatus(code: 404, body: nil)))
        XCTAssertFalse(retryable(.unacceptableStatus(code: 400, body: nil)))
        XCTAssertFalse(retryable(.decoding(message: "x")))
    }
}

// MARK: - APIClient success / error paths (URLProtocol stub)

final class APIClientTests: XCTestCase {

    private let baseURL = URL(string: "https://api.example.com")!

    override func tearDown() {
        MockAPIClient.reset()
        super.tearDown()
    }

    func testSendDecodesJSON() async throws {
        let client = MockAPIClient(baseURL: baseURL)
        client.stub(json: quoteJSON())

        let quote: Quote = try await client.send(.get("v1/quotes"))
        XCTAssertEqual(quote, Quote(symbol: "BTC", price: 42.5, currency: "AUD"))
    }

    func testGetConvenienceDecodesJSON() async throws {
        let client = MockAPIClient()
        client.stub(json: quoteJSON())

        let quote = try await client.get(URL(string: "https://api.example.com/v1/quotes")!, as: Quote.self)
        XCTAssertEqual(quote.symbol, "BTC")
    }

    func testNon2xxThrowsUnacceptableStatus() async {
        let client = MockAPIClient(baseURL: baseURL)
        client.stub(status: 404, body: Data("missing".utf8))

        do {
            let _: Quote = try await client.send(.get("v1/quotes"))
            XCTFail("Expected failure")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 404)
            if case let .unacceptableStatus(code, body) = error {
                XCTAssertEqual(code, 404)
                XCTAssertEqual(body, Data("missing".utf8))
            } else {
                XCTFail("Wrong case: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedBodyThrowsDecoding() async {
        let client = MockAPIClient(baseURL: baseURL)
        client.stub(json: Data("not json".utf8))

        do {
            let _: Quote = try await client.send(.get("v1/quotes"))
            XCTFail("Expected failure")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Wrong case: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportErrorThrowsTransport() async {
        let client = MockAPIClient(baseURL: baseURL)
        client.stub(transportError: .notConnectedToInternet)

        do {
            let _: Quote = try await client.send(.get("v1/quotes"))
            XCTFail("Expected failure")
        } catch let error as APIError {
            guard case .transport = error else { return XCTFail("Wrong case: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Retry behaviour (injected sleeper, no real waiting)

final class RetryTests: XCTestCase {

    private let baseURL = URL(string: "https://api.example.com")!

    override func tearDown() {
        StubURLProtocol.setHandler(nil)
        super.tearDown()
    }

    private func makeClient(recorder: SleepRecorder, maxRetries: Int = 3) -> LiveAPIClient {
        LiveAPIClient(session: MockAPIClient.makeSession(),
                      baseURL: baseURL,
                      retryPolicy: RetryPolicy(maxRetries: maxRetries, backoff: Backoff(base: 1, multiplier: 2, max: 60)),
                      sleeper: { await recorder.record($0) })
    }

    func testRetriesThenSucceeds() async throws {
        let recorder = SleepRecorder()
        let counter = Counter()
        let body = quoteJSON()
        StubURLProtocol.setHandler { _ in
            let attempt = counter.increment()
            return attempt <= 2 ? StubResponse(statusCode: 503) : .json(body)
        }

        let client = makeClient(recorder: recorder)
        let quote: Quote = try await client.send(.get("v1/quotes"))

        XCTAssertEqual(quote.symbol, "BTC")
        XCTAssertEqual(counter.count, 3, "Two failures then a success = three attempts")
        let delays = await recorder.delays
        XCTAssertEqual(delays, [1, 2], "Exponential backoff between the two retries")
    }

    func testNonRetryableFailsImmediately() async {
        let recorder = SleepRecorder()
        let counter = Counter()
        StubURLProtocol.setHandler { _ in
            counter.increment()
            return StubResponse(statusCode: 404)
        }

        let client = makeClient(recorder: recorder)
        do {
            let _: Quote = try await client.send(.get("v1/quotes"))
            XCTFail("Expected failure")
        } catch {
            // expected
        }
        XCTAssertEqual(counter.count, 1, "404 is not retryable")
        let delays = await recorder.delays
        XCTAssertTrue(delays.isEmpty)
    }

    func testExhaustsRetriesAndThrows() async {
        let recorder = SleepRecorder()
        let counter = Counter()
        StubURLProtocol.setHandler { _ in
            counter.increment()
            return StubResponse(statusCode: 500)
        }

        let client = makeClient(recorder: recorder, maxRetries: 2)
        do {
            let _: Quote = try await client.send(.get("v1/quotes"))
            XCTFail("Expected failure")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(counter.count, 3, "Initial attempt + 2 retries")
        let delays = await recorder.delays
        XCTAssertEqual(delays.count, 2)
    }
}

// MARK: - Fixture loader

final class FixtureTests: XCTestCase {

    func testLoadFixtureData() throws {
        let data = try Fixture.data("quote", in: .module)
        XCTAssertFalse(data.isEmpty)
    }

    func testDecodeFixture() throws {
        let quote = try Fixture.decode(Quote.self, from: "quote", in: .module)
        XCTAssertEqual(quote, Quote(symbol: "BTC", price: 42.5, currency: "AUD"))
    }

    func testMissingFixtureThrows() {
        XCTAssertThrowsError(try Fixture.data("does-not-exist", in: .module)) { error in
            guard case .fixtureNotFound = error as? APIError else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }
}

// MARK: - WebSocket typed streaming & reconnect (fake task)

/// A fake ``WebSocketTask`` that replays queued messages then throws to simulate a drop.
private final class FakeWebSocketTask: WebSocketTask, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [URLSessionWebSocketTask.Message]
    private var index = 0
    private let closeError: Error
    private(set) var pingCount = 0

    init(messages: [URLSessionWebSocketTask.Message],
         closeError: Error = URLError(.networkConnectionLost)) {
        self.messages = messages
        self.closeError = closeError
    }

    func resume() {}
    func cancel() {}

    func receive() async throws -> URLSessionWebSocketTask.Message {
        lock.lock(); defer { lock.unlock() }
        if index < messages.count {
            defer { index += 1 }
            return messages[index]
        }
        throw closeError
    }

    func sendPing() async throws {
        lock.lock(); pingCount += 1; lock.unlock()
    }
}

final class WebSocketClientTests: XCTestCase {

    private let url = URL(string: "wss://stream.example.com/ticks")!

    private func message(_ tick: Tick) -> URLSessionWebSocketTask.Message {
        .string(String(data: try! JSONEncoder().encode(tick), encoding: .utf8)!)
    }

    func testTypedStreamDecodesMessages() async {
        let ticks = [Tick(symbol: "BTC", price: 1), Tick(symbol: "ETH", price: 2), Tick(symbol: "SOL", price: 3)]
        let fake = FakeWebSocketTask(messages: ticks.map(message))
        let client = WebSocketClient(url: url,
                                     reconnect: .none,
                                     pingInterval: 0,
                                     taskFactory: { fake },
                                     sleeper: { _ in })

        var received: [Tick] = []
        for await tick in client.connect(decoding: Tick.self) {
            received.append(tick)
        }
        XCTAssertEqual(received, ticks)
    }

    func testStringStreamYieldsTextFrames() async {
        let fake = FakeWebSocketTask(messages: [.string("hello"), .string("world")])
        let client = WebSocketClient(url: url,
                                     reconnect: .none,
                                     pingInterval: 0,
                                     taskFactory: { fake },
                                     sleeper: { _ in })

        var received: [String] = []
        for await text in client.connect() {
            received.append(text)
        }
        XCTAssertEqual(received, ["hello", "world"])
    }

    func testMalformedFramesAreSkipped() async {
        let good = message(Tick(symbol: "BTC", price: 1))
        let fake = FakeWebSocketTask(messages: [.string("garbage"), good])
        let client = WebSocketClient(url: url,
                                     reconnect: .none,
                                     pingInterval: 0,
                                     taskFactory: { fake },
                                     sleeper: { _ in })

        var received: [Tick] = []
        for await tick in client.connect(decoding: Tick.self) {
            received.append(tick)
        }
        XCTAssertEqual(received, [Tick(symbol: "BTC", price: 1)])
    }

    func testReconnectsUpToMaxAttempts() async {
        let counter = Counter()
        let client = WebSocketClient(url: url,
                                     reconnect: ReconnectPolicy(maxAttempts: 2, backoff: Backoff(base: 0, multiplier: 1, max: 0)),
                                     pingInterval: 0,
                                     taskFactory: {
                                         counter.increment()
                                         return FakeWebSocketTask(messages: [])
                                     },
                                     sleeper: { _ in })

        for await _ in client.connect() { /* drains until exhausted */ }
        XCTAssertEqual(counter.count, 3, "Initial connection + 2 reconnect attempts")
    }
}
