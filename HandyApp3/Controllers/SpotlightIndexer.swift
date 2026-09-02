import CoreSpotlight
import Foundation

/// Publishes the user's things to the system Spotlight index so they can be found by name
/// from the Home Screen, and deep-linked back into.
///
/// Shaped after `NotificationScheduler.requestResync(assets:)`: the caller hands over a full
/// snapshot, records are built synchronously so only value types cross into the async task,
/// and rapid successive calls coalesce — a new reindex cancels the in-flight one.
///
/// Indexing is a full-set replace rather than an incremental diff. That is what makes it
/// correct without special cases across every path the asset set can change on — local
/// edits, a sync merge, an import, a retention purge, and factory reset — at the cost of
/// rewriting an index that is only ever a few hundred rows.
final class SpotlightIndexer {
    /// Namespaces our items so `deleteAll` can never touch another feature's index entries.
    static let domainIdentifier = "haoest.HandyApp3.asset"

    private var reindexTask: Task<Void, Never>?

    func reindex(_ assets: [Asset]) {
        let records = SpotlightRecord.records(from: assets)
        reindexTask?.cancel()
        reindexTask = Task { await Self.apply(records) }
    }

    private static func apply(_ records: [SpotlightRecord]) async {
        let index = CSSearchableIndex.default()
        // Replace wholesale: the delete is what retires renamed, deleted and purged things.
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
        guard !Task.isCancelled, !records.isEmpty else { return }

        let items = records.map { record -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = record.name
            attributes.contentDescription = record.categoryName.isEmpty ? nil : record.categoryName
            attributes.keywords = [record.name, record.categoryName].filter { !$0.isEmpty }
            return CSSearchableItem(
                // The asset's UUID string, so the deep link back is a plain UUID(uuidString:).
                uniqueIdentifier: record.id.uuidString,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
        try? await index.indexSearchableItems(items)
    }
}
