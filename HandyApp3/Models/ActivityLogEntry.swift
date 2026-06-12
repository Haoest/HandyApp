import Foundation

/// What kind of record an ActivityLogEntry refers to.
enum LoggedRecordKind: String {
    case asset, event, transaction
}

/// An immutable record of a domain-record creation. Entries hold only IDs;
/// names are resolved live from the store at render time.
struct ActivityLogEntry: Identifiable, Equatable {
    /// The log entry's own identity.
    let id: UUID
    /// UUID of the created asset/event/transaction.
    let recordID: UUID
    let kind: LoggedRecordKind
    /// The asset an event/transaction was logged to; nil for asset entries.
    let owningAssetID: UUID?
    let timestamp: Date

    init(
        recordID: UUID,
        kind: LoggedRecordKind,
        owningAssetID: UUID? = nil,
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.recordID = recordID
        self.kind = kind
        self.owningAssetID = owningAssetID
        self.timestamp = timestamp
    }
}
