import Foundation
import PersistenceKit

/// Offline-first sync built on **CRDTs**: the merge logic is local, deterministic, and fully
/// testable without any account, while the network transport sits behind a protocol.
///
/// The convergence guarantee comes from the ``Mergeable`` laws (commutative, associative,
/// idempotent merges): replicas can edit offline and, once they exchange state in any order, end up
/// identical with no data loss.
///
/// > Note: The CloudKit transport (``CloudKitTransport``) needs a **paid Apple Developer account**
/// > and an iCloud container, so it ships as a documented skeleton. Use ``MockTransport`` for tests,
/// > previews, and sandbox builds — the merge code is identical either way.
///
/// ## Topics
/// ### CRDT building blocks
/// - ``Mergeable``
/// - ``LWWRegister``
/// - ``ORSet``
/// ### Syncable entity
/// - ``MergeableDocument``
/// ### Transport
/// - ``SyncTransport``
/// - ``MockTransport``
/// - ``SyncEngine``
/// - ``CloudKitTransport``
/// - ``SyncError``
public enum SyncKit {
    public static let info = "Offline-first CRDT merge + CloudKit transport (transport deferred)."
}
