#if canImport(CloudKit)
import Foundation
import CloudKit

/// A ``SyncTransport`` backed by CloudKit — **skeleton**, requires a paid account.
///
/// > Important: CloudKit needs a **paid Apple Developer account** plus, on the app target:
/// > - the **iCloud** capability with **CloudKit** enabled,
/// > - `com.apple.developer.icloud-services` set to include `CloudKit`,
/// > - `com.apple.developer.icloud-container-identifiers` listing your container
/// >   (`iCloud.com.example.app`).
/// >
/// > It also can't run in unit tests or the Simulator without that container, so this type is not
/// > exercised by the test suite. The merge logic it relies on (``Mergeable``) is, however, fully
/// > tested via ``MockTransport``.
///
/// ## Record mapping
/// Each document is stored as one `CKRecord` whose `recordName` is the document id. The whole
/// `Mergeable & Codable` document is JSON-encoded into a single `payload` field. `push` does a
/// **fetch → merge → save** so it converges with concurrent remote writes rather than overwriting
/// them; a production version would also retry on `CKError.serverRecordChanged`.
///
/// ```swift
/// let container = CKContainer(identifier: "iCloud.com.example.app")
/// let transport = CloudKitTransport<MergeableDocument>(database: container.privateCloudDatabase)
/// ```
public struct CloudKitTransport<Document: Mergeable & Codable & Sendable>: SyncTransport {
    /// The CloudKit database (e.g. `container.privateCloudDatabase`).
    public let database: CKDatabase
    /// The CloudKit record type used for documents.
    public let recordType: String
    private let payloadKey = "payload"

    /// Create a transport.
    ///
    /// - Parameters:
    ///   - database: The CloudKit database to read/write.
    ///   - recordType: Record type name. Default `"MergeableDocument"`.
    public init(database: CKDatabase, recordType: String = "MergeableDocument") {
        self.database = database
        self.recordType = recordType
    }

    public func push(_ document: Document, for id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        let record: CKRecord
        let toSave: Document

        if let existing = try? await database.record(for: recordID) {
            // Merge with the remote record so we never clobber newer concurrent state.
            toSave = (decode(existing)?.merged(with: document)) ?? document
            record = existing
        } else {
            toSave = document
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record[payloadKey] = try encode(toSave) as CKRecordValue
        _ = try await database.save(record)
    }

    public func pull(_ id: String) async throws -> Document? {
        let recordID = CKRecord.ID(recordName: id)
        guard let record = try? await database.record(for: recordID) else { return nil }
        return decode(record)
    }

    public func pullAll() async throws -> [String: Document] {
        // A real implementation queries with `CKQuery(recordType:predicate:)`, which requires the
        // record type to be marked queryable in the CloudKit schema. Left unimplemented in the
        // skeleton so it isn't mistaken for a working, schema-configured query.
        throw SyncError.notConfigured("CloudKitTransport.pullAll requires a queryable CloudKit schema.")
    }

    // MARK: - Codec

    private func encode(_ document: Document) throws -> Data {
        try JSONEncoder().encode(document)
    }

    private func decode(_ record: CKRecord) -> Document? {
        guard let data = record[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(Document.self, from: data)
    }
}
#endif
