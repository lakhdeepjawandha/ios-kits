import Foundation
import PersistenceKit

/// Offline-first sync. The CRDT merge logic (the portfolio centerpiece for #45) lives here
/// and is fully testable without a paid account. The CloudKit transport is wired later,
/// once you have an Apple Developer account + iCloud container.
public enum SyncKit {
    public static let info = "Offline-first CRDT merge + CloudKit transport (transport deferred)."
}

/// Last-write-wins register — the simplest CRDT building block. Expand to add/remove sets
/// for collections when you build #45 Envelope.
public struct LWWRegister<Value: Equatable>: Equatable {
    public private(set) var value: Value
    public private(set) var timestamp: Date

    public init(_ value: Value, timestamp: Date = .now) {
        self.value = value
        self.timestamp = timestamp
    }

    public mutating func merge(_ other: LWWRegister<Value>) {
        if other.timestamp > timestamp {
            value = other.value
            timestamp = other.timestamp
        }
    }
}
