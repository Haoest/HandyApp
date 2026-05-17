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

    static let sortOrderIncrement: Double = 10

    init(id: UUID = UUID(), definition: PropertyDefinition, value: StoredValue? = nil, sortOrder: Double = 0) {
        self.id = id
        self.definition = definition
        self.value = value
        self.sortOrder = sortOrder
    }

    static func == (lhs: AssetProperty, rhs: AssetProperty) -> Bool {
        lhs.id == rhs.id
    }
}
