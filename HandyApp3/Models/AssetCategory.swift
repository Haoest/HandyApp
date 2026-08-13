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
    /// a minimal tombstone (`name`/`iconName` blanked, `propertyTemplates` emptied). Monotone —
    /// never goes back to false. The record itself is kept forever specifically so this stays
    /// visible to every peer: a stale device that still holds the full category must see the
    /// strip and re-apply it, not resurrect the payload by unioning it back in on the next sync.
    var isPurged: Bool = false

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

    static func == (lhs: AssetCategory, rhs: AssetCategory) -> Bool {
        lhs.id == rhs.id
    }
}
