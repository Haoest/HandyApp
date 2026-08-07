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

    /// Absolute instant of the last edit to this property's definition or value.
    /// `Date` is timezone-free; persisted as ISO-8601 UTC.
    var modifyDate: Date

    static let sortOrderIncrement: Double = 10

    init(
        id: UUID = UUID(),
        definition: PropertyDefinition,
        value: StoredValue? = nil,
        sortOrder: Double = 0,
        modifyDate: Date = Date()
    ) {
        self.id = id
        self.definition = definition
        self.value = value
        self.sortOrder = sortOrder
        self.modifyDate = modifyDate
    }

    /// Stamps the property as edited now. Called from AssetStore after any definition or value write.
    func touch(_ date: Date = Date()) {
        modifyDate = date
    }

    static func == (lhs: AssetProperty, rhs: AssetProperty) -> Bool {
        lhs.id == rhs.id
    }
}
