import Foundation

/// A self-contained, per-asset property: bundles a PropertyDefinition (schema)
/// with an optional PropertyValue (data) and lives exclusively on one Asset instance.
///
/// Unlike category-level PropertyDefinitions, an AssetProperty is not shared across
/// assets — it is defined and owned by a single asset.
final class AssetProperty: Identifiable, Equatable {
    let id: UUID
    var definition: PropertyDefinition
    var value: PropertyValue?

    init(id: UUID = UUID(), definition: PropertyDefinition, value: PropertyValue? = nil) {
        self.id = id
        self.definition = definition
        self.value = value
    }

    static func == (lhs: AssetProperty, rhs: AssetProperty) -> Bool {
        lhs.id == rhs.id
    }
}
