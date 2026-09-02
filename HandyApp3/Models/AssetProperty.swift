import Foundation
import Observation

/// A self-contained property: bundles a PropertyDefinition (schema) with an
/// optional StoredValue (data). Lives on one Asset instance — not shared across assets.
@Observable
final class AssetProperty: Identifiable, Equatable {
    let id: UUID
    var definition: PropertyDefinition
    var value: StoredValue?
    var sortOrder: Double

    /// Absolute instant of the last edit to this property's definition or value,
    /// including its tombstoning. `Date` is timezone-free; persisted as ISO-8601 UTC.
    var modifyDate: Date

    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    /// Set once the user edits this property's *definition* (not its value) — a rename, a
    /// Required toggle, a type change, a maxLength change. `BuiltInTypes.upgradeBuiltInCategories`
    /// skips a field that carries it, so a user's edit to a built-in template field is never
    /// reverted to canonical on a later launch. Sticky: only ever set true, never cleared back —
    /// `SnapshotReconciler.joinAssetProperty` ORs it across peers for the same reason.
    var isUserEdited: Bool = false

    static let sortOrderIncrement: Double = 10

    init(
        id: UUID = UUID(),
        definition: PropertyDefinition,
        value: StoredValue? = nil,
        sortOrder: Double = 0,
        modifyDate: Date = Date(),
        isUserEdited: Bool = false
    ) {
        self.id = id
        self.definition = definition
        self.value = value
        self.sortOrder = sortOrder
        self.modifyDate = modifyDate
        self.isUserEdited = isUserEdited
    }

    /// Stamps the property as edited now. Called from AssetStore after any definition or value write.
    func touch(_ date: Date = Date()) {
        modifyDate = date
    }

    static func == (lhs: AssetProperty, rhs: AssetProperty) -> Bool {
        lhs.id == rhs.id
    }
}
