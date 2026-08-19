import Foundation
import Observation

/// A physical asset owned by the user (e.g. "My House", "2022 Toyota Camry").
@Observable
final class Asset: Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdDate: Date
    var modifiedDate: Date

    /// Absolute instant the asset's parent link last changed (attached, detached, or re-parented).
    /// Initialized at creation — being a root is itself a parentage state.
    var parentageModifyDate: Date

    /// Absolute instant `name` or the tombstone (`isDeleted`/`deletedAt`) last changed. Separate
    /// from `modifiedDate`, which is a rollup bumped by every child mutation (a property edit, a
    /// photo add, ...) and so cannot serve as a merge stamp for the asset's own head fields —
    /// whole-record last-writer-wins on `modifiedDate` would let an unrelated later child edit
    /// on one device beat an earlier delete on another, resurrecting it.
    var headModifyDate: Date

    /// The category this asset was created from.
    var category: AssetCategory

    /// Properties copied from the category's templates at creation time.
    /// Values are filled in per-instance; definitions come from the category snapshot. A later
    /// edit to the category's templates does not reach this array automatically — see
    /// `AssetStore.propagateTemplates(forCategoryID:)`.
    var baseProperties: [AssetProperty]

    /// Per-instance properties defined by the user specifically for this asset.
    var customProperties: [AssetProperty]

    var photos: [Photo] = []
    var events: [Event] = []
    var transactions: [Transaction] = []

    /// ID of the asset that directly contains this one. Nil means top-level.
    var parentID: UUID?

    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    /// Set once `AssetStore.purgeHardDeleted`/`hardDeleteAsset` has stripped this record to a
    /// minimal tombstone (photos/events/transactions/customProperties/baseProperties emptied,
    /// detached from its parent). The record itself is kept forever specifically so this stays
    /// visible to every peer: a stale device that still holds the full asset must see the strip
    /// and re-apply it, not resurrect the payload by unioning it back in on the next sync.
    ///
    /// Cleared by an explicit user-initiated import (`AssetStore.importJSON`) carrying a live
    /// copy of this asset — an import that says a record is alive is treated as intent to bring
    /// it back, rebuilding content and parentage from the incoming record. Cloud sync
    /// (`applyInPlace`/`SnapshotReconciler.joinAsset`) also clears it, but only when the local
    /// content is strictly newer than the purge decision (`purgedAt`) — see `purgedAt`'s doc
    /// comment. Otherwise a purge always wins there.
    var isPurged: Bool = false

    /// Instant this asset was actually stripped — set by `purgeInPlace`/`purgeHardDeleted`/
    /// `SnapshotReconciler.reap` alongside `isPurged`. Distinct from `deletedAt` (when the user
    /// *decided* to delete): purge normally happens automatically ~14 days later as retention
    /// housekeeping, so a device that edits this asset offline during that window has content
    /// newer than the delete but older than the purge. `SnapshotReconciler.joinAsset` compares
    /// against this, not `deletedAt`, to decide whether a purge is allowed to destroy that
    /// content — see the gate documented there. `nil` for a record purged before this field
    /// existed, which makes it permanently unrefusable (matches the pre-gate behavior).
    var purgedAt: Date? = nil

    /// Resolved in-memory reference to the parent. Set by AssetStore hierarchy methods.
    weak var parent: Asset?

    /// Direct children of this asset. Mutated exclusively through AssetStore hierarchy methods.
    private(set) var children: [Asset] = []

    init(
        id: UUID = UUID(),
        name: String,
        category: AssetCategory,
        baseProperties: [AssetProperty] = [],
        customProperties: [AssetProperty] = [],
        parentID: UUID? = nil,
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        parentageModifyDate: Date = Date(),
        headModifyDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.baseProperties = baseProperties
        self.customProperties = customProperties
        self.parentID = parentID
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.parentageModifyDate = parentageModifyDate
        self.headModifyDate = headModifyDate
    }

    /// True when this asset's own content (a base/custom property edit, a photo/event/
    /// transaction add) was made after `deletedAt` — or after an already-recorded purge
    /// attempt's `purgedAt`, if later. Both `AssetStore.purgeHardDeleted`'s automatic retention
    /// sweep and `SnapshotReconciler.joinAsset`'s sync-merge gate refuse to strip a record in
    /// this state, so it sits in Trash indefinitely (restorable, or removable via an explicit
    /// "delete now") instead of silently losing that content when the tombstone ages out.
    /// `false` while still live — protection is only meaningful for something already deleted.
    ///
    /// `purgedAt` falls back to `.distantPast`, not `.distantFuture`, here — unlike
    /// `SnapshotReconciler`'s DTO-level gate, which is only ever evaluated on a record that
    /// already carries `isPurged == true` (where a nil `purgedAt` specifically flags a
    /// pre-migration legacy record that must stay permanently unrefusable). This property is
    /// evaluated on a record that is NOT purged — `purgedAt` is nil here in the ordinary case
    /// (no purge attempted yet) and must be ignored rather than treated as an infinite block,
    /// or this would report every deleted asset as unprotected regardless of content.
    var isProtectedFromAutoPurge: Bool {
        guard isDeleted, !isPurged else { return false }
        let content = max(modifiedDate, headModifyDate).timeIntervalSince1970.rounded(.down)
        let threshold = max(deletedAt ?? .distantPast, purgedAt ?? .distantPast)
            .timeIntervalSince1970.rounded(.down)
        return content > threshold
    }

    // MARK: - Property value convenience

    /// Returns the stored value for a given definition id, checking base then custom properties.
    func value(for definitionID: UUID) -> StoredValue? {
        if let bp = liveBaseProperties.first(where: { $0.definition.id == definitionID }) { return bp.value }
        return liveCustomProperties.first(where: { $0.definition.id == definitionID })?.value
    }

    /// Returns the custom AssetProperty for a given definition id, if it exists.
    func customProperty(for definitionID: UUID) -> AssetProperty? {
        liveCustomProperties.first { $0.definition.id == definitionID }
    }

    // MARK: - Inline record convenience

    /// Inline records excluding tombstones. Deleted events/transactions/photos/base/custom
    /// properties stay in the arrays until `AssetStore.purgeHardDeleted` reaps them, so every
    /// read site — display, lookup, notification planning, paywall counting — must go through these.
    var livePhotos: [Photo] { photos.filter { !$0.isDeleted } }
    var liveEvents: [Event] { events.filter { !$0.isDeleted } }
    var liveTransactions: [Transaction] { transactions.filter { !$0.isDeleted } }
    var liveBaseProperties: [AssetProperty] { baseProperties.filter { !$0.isDeleted } }
    var liveCustomProperties: [AssetProperty] { customProperties.filter { !$0.isDeleted } }

    // MARK: - Hierarchy traversal

    /// Ordered chain from the root ancestor down to (but not including) this asset.
    var ancestors: [Asset] {
        var chain: [Asset] = []
        var cursor = parent
        while let p = cursor {
            chain.insert(p, at: 0)
            cursor = p.parent
        }
        return chain
    }

    /// All assets in the subtree rooted at this asset (breadth-first, excluding self).
    var descendants: [Asset] {
        var result: [Asset] = []
        var queue = children
        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)
            queue.append(contentsOf: node.children)
        }
        return result
    }

    var isRoot: Bool { parent == nil }

    // MARK: - Internal child management (called only by AssetStore)

    /// Pass `stampParentage: false` only when rehydrating an already-recorded link — loading a
    /// snapshot or wiring merged assets — so the stored timestamp survives instead of resetting.
    func _addChild(_ child: Asset, stampParentage: Bool = true) {
        guard !children.contains(where: { $0.id == child.id }) else { return }
        children.append(child)
        child.parent = self
        child.parentID = self.id
        if stampParentage { child.stampParentage() }
    }

    func _removeChild(_ child: Asset, stampParentage: Bool = true) {
        let wasLinked = children.contains(where: { $0.id == child.id }) || child.parentID != nil
        children.removeAll { $0.id == child.id }
        child.parent = nil
        child.parentID = nil
        if stampParentage && wasLinked { child.stampParentage() }
    }

    /// A move changes the child's record, so both timestamps advance.
    private func stampParentage(_ date: Date = Date()) {
        parentageModifyDate = date
        modifiedDate = date
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }
}
