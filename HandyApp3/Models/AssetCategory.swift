import Foundation
import Observation

/// A named template that defines the base properties for a class of assets.
/// When an Asset is created from a category, each template entry is deep-copied
/// into the asset's `baseProperties`.
@Observable
final class AssetCategory: Identifiable, Equatable {
    let id: UUID
    var name: String
    var iconName: String
    /// The property templates that get stamped onto new assets of this category. Includes
    /// tombstoned entries — use `liveTemplates` for anything that shouldn't show a removed one.
    var propertyTemplates: [AssetProperty]
    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    /// Set once `AssetStore.purgeHardDeleted`/`hardDeleteCategory` has stripped this record to
    /// a minimal tombstone (`name`/`iconName` blanked, `propertyTemplates` emptied). The record
    /// itself is kept forever specifically so this stays visible to every peer: a stale device
    /// that still holds the full category must see the strip and re-apply it, not resurrect the
    /// payload by unioning it back in on the next sync.
    ///
    /// Cleared by an explicit user-initiated import (`AssetStore.importJSON`) carrying a live
    /// copy of this category, which also restores the blanked `name`/`iconName`. Cloud sync
    /// (`applyInPlace`/`SnapshotReconciler.joinCategory`) also clears it, but only when local
    /// content is strictly newer than the purge decision (`purgedAt`) — see `purgedAt`'s doc
    /// comment. Otherwise a purge always wins there.
    var isPurged: Bool = false

    /// Instant this category was actually stripped — set by `purgeCategoryInPlace`/
    /// `purgeHardDeleted`/`SnapshotReconciler.reap` alongside `isPurged`. Distinct from
    /// `deletedAt` (when the user *decided* to delete): purge normally happens automatically
    /// ~14 days later as retention housekeeping, so a device that edits this category's
    /// templates offline during that window has content newer than the delete but older than
    /// the purge. `SnapshotReconciler.joinCategory` compares against this, not `deletedAt`, to
    /// decide whether a purge is allowed to destroy that content. `nil` for a record purged
    /// before this field existed, which makes it permanently unrefusable.
    var purgedAt: Date? = nil

    /// Absolute instant `name`, `iconName`, or the tombstone last changed. `AssetCategory` has
    /// no rollup field the way `Asset.modifiedDate` does, so this covers the whole header as
    /// one record.
    var modifyDate: Date

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "square.grid.2x2",
        propertyTemplates: [AssetProperty] = [],
        modifyDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.propertyTemplates = propertyTemplates
        self.modifyDate = modifyDate
    }

    /// `propertyTemplates` filtering out removed fields — mirrors `Asset.liveCustomProperties`.
    var liveTemplates: [AssetProperty] { propertyTemplates.filter { !$0.isDeleted } }

    /// See `Asset.isProtectedFromAutoPurge`'s doc comment — identical rule (including why
    /// `purgedAt` falls back to `.distantPast` here, not `.distantFuture`), folding in template
    /// `modifyDate`s (since `addTemplateProperty` and friends don't bump this category's own
    /// `modifyDate`) rather than a `headModifyDate`, which `AssetCategory` has no equivalent of.
    var isProtectedFromAutoPurge: Bool {
        guard isDeleted, !isPurged else { return false }
        let templateMax = propertyTemplates.map(\.modifyDate).max() ?? .distantPast
        let content = max(modifyDate, templateMax).timeIntervalSince1970.rounded(.down)
        let threshold = max(deletedAt ?? .distantPast, purgedAt ?? .distantPast)
            .timeIntervalSince1970.rounded(.down)
        return content > threshold
    }

    static func == (lhs: AssetCategory, rhs: AssetCategory) -> Bool {
        lhs.id == rhs.id
    }
}
