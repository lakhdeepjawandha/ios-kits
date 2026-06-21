import Foundation
import UserNotifications

// MARK: - Trigger

/// Describes when a local notification should fire.
///
/// Build one directly, or use the ``after(_:)`` / ``at(_:calendar:)`` conveniences for the
/// common one-off cases.
public enum NotificationTrigger: Equatable, Sendable {
    /// Fires after `interval` seconds, optionally repeating.
    ///
    /// The system requires `interval > 0`, and `interval >= 60` when `repeats` is `true`.
    case timeInterval(TimeInterval, repeats: Bool)

    /// Fires when the current date matches the given components, optionally repeating.
    ///
    /// For example, `DateComponents(hour: 9, minute: 0)` with `repeats: true` fires daily at 9am.
    case calendar(DateComponents, repeats: Bool)

    /// A one-off trigger that fires once, `interval` seconds from scheduling.
    public static func after(_ interval: TimeInterval) -> NotificationTrigger {
        .timeInterval(interval, repeats: false)
    }

    /// A one-off trigger that fires once at the given absolute date.
    /// - Parameters:
    ///   - date: The date to fire at.
    ///   - calendar: The calendar used to decompose `date`. Defaults to `.current`.
    public static func at(_ date: Date, calendar: Calendar = .current) -> NotificationTrigger {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return .calendar(components, repeats: false)
    }
}

// MARK: - Errors

/// Errors raised when a ``NotificationRequest`` is invalid for scheduling.
public enum NotificationSchedulingError: Error, Equatable, Sendable {
    /// The request identifier was empty or whitespace-only.
    case emptyIdentifier
    /// A time-interval trigger had a non-positive interval.
    case nonPositiveInterval
    /// A repeating time-interval trigger was shorter than the system minimum.
    case repeatingIntervalTooShort(minimum: TimeInterval)
}

// MARK: - Request model

/// A typed, value-semantic description of a local notification.
///
/// Modeling the request as a plain value keeps it testable without touching the system
/// notification center: validate it with ``validate()`` and convert it with
/// ``makeUNNotificationRequest()``.
///
/// ```swift
/// let request = NotificationRequest(
///     identifier: "daily-summary",
///     title: "Daily summary",
///     body: "Your portfolio moved +1.2% today.",
///     trigger: .calendar(DateComponents(hour: 18), repeats: true)
/// )
/// try await scheduler.schedule(request)
/// ```
public struct NotificationRequest: Equatable, Sendable {
    /// Unique identifier; scheduling another request with the same id replaces it.
    public var identifier: String
    /// The notification's title.
    public var title: String
    /// The notification's body text.
    public var body: String
    /// Whether to play the default notification sound. Defaults to `true`.
    public var playsSound: Bool
    /// Optional badge number to set on the app icon.
    public var badge: Int?
    /// Arbitrary string metadata delivered in the notification's `userInfo`.
    public var userInfo: [String: String]
    /// When the notification fires.
    public var trigger: NotificationTrigger

    /// The minimum interval (seconds) the system allows for a *repeating* time-interval trigger.
    public static let minimumRepeatingInterval: TimeInterval = 60

    /// Creates a notification request.
    /// - Parameters:
    ///   - identifier: Unique identifier; reusing one replaces the prior request.
    ///   - title: The title text.
    ///   - body: The body text.
    ///   - playsSound: Whether to play the default sound. Defaults to `true`.
    ///   - badge: Optional app-icon badge number. Defaults to `nil`.
    ///   - userInfo: Optional string metadata. Defaults to empty.
    ///   - trigger: When the notification fires.
    public init(
        identifier: String,
        title: String,
        body: String,
        playsSound: Bool = true,
        badge: Int? = nil,
        userInfo: [String: String] = [:],
        trigger: NotificationTrigger
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.playsSound = playsSound
        self.badge = badge
        self.userInfo = userInfo
        self.trigger = trigger
    }

    /// Validates that this request can be scheduled.
    /// - Throws: ``NotificationSchedulingError`` if the identifier or trigger is invalid.
    public func validate() throws {
        if identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NotificationSchedulingError.emptyIdentifier
        }
        switch trigger {
        case .timeInterval(let interval, let repeats):
            if interval <= 0 {
                throw NotificationSchedulingError.nonPositiveInterval
            }
            if repeats && interval < Self.minimumRepeatingInterval {
                throw NotificationSchedulingError.repeatingIntervalTooShort(
                    minimum: Self.minimumRepeatingInterval
                )
            }
        case .calendar:
            break
        }
    }

    /// Converts this value into a system `UNNotificationRequest`.
    ///
    /// - Important: Call ``validate()`` first; constructing a time-interval trigger with a
    ///   non-positive interval traps inside UserNotifications.
    public func makeUNNotificationRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playsSound { content.sound = .default }
        if let badge { content.badge = NSNumber(value: badge) }
        if !userInfo.isEmpty { content.userInfo = userInfo }

        let systemTrigger: UNNotificationTrigger
        switch trigger {
        case .timeInterval(let interval, let repeats):
            systemTrigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: repeats)
        case .calendar(let components, let repeats):
            systemTrigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        }

        return UNNotificationRequest(identifier: identifier, content: content, trigger: systemTrigger)
    }
}

// MARK: - Center abstraction

/// The subset of `UNUserNotificationCenter` used by ``NotificationScheduler``.
///
/// Abstracting it behind a protocol lets you inject a mock in tests instead of the real,
/// permission-gated system center.
public protocol UserNotificationCentering {
    /// Requests authorization for the given options, returning whether it was granted.
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    /// Schedules a notification request.
    func add(_ request: UNNotificationRequest) async throws
    /// Returns the currently pending (not-yet-delivered) requests.
    func pendingRequests() async -> [UNNotificationRequest]
    /// Cancels pending requests with the given identifiers.
    func removePendingRequests(identifiers: [String])
    /// Cancels all pending requests.
    func removeAllPendingRequests()
}

extension UNUserNotificationCenter: UserNotificationCentering {
    public func pendingRequests() async -> [UNNotificationRequest] {
        await pendingNotificationRequests()
    }

    public func removePendingRequests(identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeAllPendingRequests() {
        removeAllPendingNotificationRequests()
    }
}

// MARK: - Scheduler

/// Schedules and manages local notifications on top of `UNUserNotificationCenter`.
///
/// ```swift
/// let scheduler = NotificationScheduler()
/// guard try await scheduler.requestAuthorization() else { return }
/// try await scheduler.schedule(
///     NotificationRequest(identifier: "reminder", title: "Reminder",
///                         body: "Time to review.", trigger: .after(3600))
/// )
/// ```
public final class NotificationScheduler {
    private let center: any UserNotificationCentering

    /// Creates a scheduler.
    /// - Parameter center: The notification center to drive. Defaults to the shared system center;
    ///   inject a mock conforming to ``UserNotificationCentering`` in tests.
    public init(center: any UserNotificationCentering = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Requests notification authorization from the user.
    /// - Parameter options: The authorization options to request. Defaults to alert, sound, and badge.
    /// - Returns: `true` if authorization was granted.
    @discardableResult
    public func requestAuthorization(
        options: UNAuthorizationOptions = [.alert, .sound, .badge]
    ) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    /// Validates and schedules a notification.
    /// - Parameter request: The request to schedule.
    /// - Throws: ``NotificationSchedulingError`` if invalid, or any error from the center.
    public func schedule(_ request: NotificationRequest) async throws {
        try request.validate()
        try await center.add(request.makeUNNotificationRequest())
    }

    /// Cancels a single pending notification by identifier.
    public func cancel(identifier: String) {
        center.removePendingRequests(identifiers: [identifier])
    }

    /// Cancels pending notifications by identifier.
    public func cancel(identifiers: [String]) {
        center.removePendingRequests(identifiers: identifiers)
    }

    /// Cancels all pending notifications.
    public func cancelAll() {
        center.removeAllPendingRequests()
    }

    /// Lists the currently pending notification requests.
    public func pending() async -> [UNNotificationRequest] {
        await center.pendingRequests()
    }
}
