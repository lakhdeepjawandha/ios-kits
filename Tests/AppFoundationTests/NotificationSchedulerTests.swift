import XCTest
import UserNotifications
@testable import AppFoundation

// MARK: - Mock center

/// In-memory stand-in for `UNUserNotificationCenter` used to test the scheduler's pure logic.
private final class MockCenter: UserNotificationCentering, @unchecked Sendable {
    var authorizationResult = true
    var authorizationError: Error?
    private(set) var requestedOptions: UNAuthorizationOptions?
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []
    private(set) var removedAllCount = 0

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedOptions = options
        if let authorizationError { throw authorizationError }
        return authorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        added.removeAll { $0.identifier == request.identifier } // replace, like the system
        added.append(request)
    }

    func pendingRequests() async -> [UNNotificationRequest] { added }

    func removePendingRequests(identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        added.removeAll { identifiers.contains($0.identifier) }
    }

    func removeAllPendingRequests() {
        removedAllCount += 1
        added.removeAll()
    }
}

// MARK: - Request modeling

final class NotificationRequestModelTests: XCTestCase {

    func testValidationRejectsEmptyIdentifier() {
        let request = NotificationRequest(identifier: "  ", title: "T", body: "B", trigger: .after(10))
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? NotificationSchedulingError, .emptyIdentifier)
        }
    }

    func testValidationRejectsNonPositiveInterval() {
        let request = NotificationRequest(identifier: "id", title: "T", body: "B",
                                          trigger: .timeInterval(0, repeats: false))
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? NotificationSchedulingError, .nonPositiveInterval)
        }
    }

    func testValidationRejectsShortRepeatingInterval() {
        let request = NotificationRequest(identifier: "id", title: "T", body: "B",
                                          trigger: .timeInterval(30, repeats: true))
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? NotificationSchedulingError,
                           .repeatingIntervalTooShort(minimum: 60))
        }
    }

    func testValidationAcceptsValidTriggers() {
        XCTAssertNoThrow(try NotificationRequest(identifier: "id", title: "T", body: "B",
                                                 trigger: .after(10)).validate())
        XCTAssertNoThrow(try NotificationRequest(identifier: "id", title: "T", body: "B",
                                                 trigger: .timeInterval(60, repeats: true)).validate())
        XCTAssertNoThrow(try NotificationRequest(identifier: "id", title: "T", body: "B",
                                                 trigger: .calendar(DateComponents(hour: 9), repeats: true)).validate())
    }

    func testAfterConvenienceBuildsOneOffInterval() {
        XCTAssertEqual(NotificationTrigger.after(42), .timeInterval(42, repeats: false))
    }

    func testAtConvenienceBuildsNonRepeatingCalendarTrigger() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2030, month: 6, day: 1, hour: 8, minute: 30))!

        guard case let .calendar(components, repeats) = NotificationTrigger.at(date, calendar: calendar) else {
            return XCTFail("Expected a calendar trigger")
        }
        XCTAssertFalse(repeats)
        XCTAssertEqual(components.year, 2030)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 30)
    }

    func testMakeUNRequestMapsContentAndIdentifier() {
        let request = NotificationRequest(
            identifier: "summary",
            title: "Title",
            body: "Body",
            playsSound: true,
            badge: 3,
            userInfo: ["k": "v"],
            trigger: .after(15)
        )
        let un = request.makeUNNotificationRequest()

        XCTAssertEqual(un.identifier, "summary")
        XCTAssertEqual(un.content.title, "Title")
        XCTAssertEqual(un.content.body, "Body")
        XCTAssertNotNil(un.content.sound)
        XCTAssertEqual(un.content.badge, NSNumber(value: 3))
        XCTAssertEqual(un.content.userInfo["k"] as? String, "v")
    }

    func testMakeUNRequestMapsTimeIntervalTrigger() {
        let un = NotificationRequest(identifier: "i", title: "T", body: "B",
                                     trigger: .timeInterval(90, repeats: true)).makeUNNotificationRequest()
        let trigger = try? XCTUnwrap(un.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger?.timeInterval, 90)
        XCTAssertEqual(trigger?.repeats, true)
    }

    func testMakeUNRequestMapsCalendarTrigger() {
        let un = NotificationRequest(identifier: "i", title: "T", body: "B",
                                     trigger: .calendar(DateComponents(hour: 9, minute: 15), repeats: true)).makeUNNotificationRequest()
        let trigger = try? XCTUnwrap(un.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger?.repeats, true)
        XCTAssertEqual(trigger?.dateComponents.hour, 9)
        XCTAssertEqual(trigger?.dateComponents.minute, 15)
    }

    func testMakeUNRequestOmitsSoundWhenDisabled() {
        let un = NotificationRequest(identifier: "i", title: "T", body: "B",
                                     playsSound: false, trigger: .after(10)).makeUNNotificationRequest()
        XCTAssertNil(un.content.sound)
    }
}

// MARK: - Scheduler logic

final class NotificationSchedulerTests: XCTestCase {

    func testRequestAuthorizationForwardsOptionsAndResult() async throws {
        let center = MockCenter()
        center.authorizationResult = false
        let scheduler = NotificationScheduler(center: center)

        let granted = try await scheduler.requestAuthorization(options: [.alert])
        XCTAssertFalse(granted)
        XCTAssertEqual(center.requestedOptions, [.alert])
    }

    func testScheduleAddsValidRequest() async throws {
        let center = MockCenter()
        let scheduler = NotificationScheduler(center: center)

        try await scheduler.schedule(
            NotificationRequest(identifier: "a", title: "T", body: "B", trigger: .after(60))
        )
        let pending = await scheduler.pending()
        XCTAssertEqual(pending.map(\.identifier), ["a"])
    }

    func testScheduleRejectsInvalidRequestWithoutCallingCenter() async {
        let center = MockCenter()
        let scheduler = NotificationScheduler(center: center)

        do {
            try await scheduler.schedule(
                NotificationRequest(identifier: "", title: "T", body: "B", trigger: .after(60))
            )
            XCTFail("Expected validation to throw")
        } catch {
            XCTAssertEqual(error as? NotificationSchedulingError, .emptyIdentifier)
        }
        let pending = await scheduler.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testCancelByIdentifierRemovesOnlyThatRequest() async throws {
        let center = MockCenter()
        let scheduler = NotificationScheduler(center: center)
        try await scheduler.schedule(NotificationRequest(identifier: "a", title: "T", body: "B", trigger: .after(60)))
        try await scheduler.schedule(NotificationRequest(identifier: "b", title: "T", body: "B", trigger: .after(60)))

        scheduler.cancel(identifier: "a")

        let pending = await scheduler.pending()
        XCTAssertEqual(pending.map(\.identifier), ["b"])
        XCTAssertEqual(center.removedIdentifiers, ["a"])
    }

    func testCancelAllClearsEverything() async throws {
        let center = MockCenter()
        let scheduler = NotificationScheduler(center: center)
        try await scheduler.schedule(NotificationRequest(identifier: "a", title: "T", body: "B", trigger: .after(60)))

        scheduler.cancelAll()

        let pending = await scheduler.pending()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(center.removedAllCount, 1)
    }

    func testScheduleReplacesRequestWithSameIdentifier() async throws {
        let center = MockCenter()
        let scheduler = NotificationScheduler(center: center)
        try await scheduler.schedule(NotificationRequest(identifier: "a", title: "One", body: "B", trigger: .after(60)))
        try await scheduler.schedule(NotificationRequest(identifier: "a", title: "Two", body: "B", trigger: .after(60)))

        let pending = await scheduler.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.content.title, "Two")
    }
}
