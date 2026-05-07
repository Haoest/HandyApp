import Foundation

/// A user-definable asset category (e.g. House, Car, Appliance, or any custom type).
/// Categories own the canonical set of PropertyDefinitions for their assets.
final class AssetCategory: Identifiable, Equatable {
    let id: UUID
    var name: String
    /// The ordered list of property definitions that assets of this category can have.
    var propertyDefinitions: [PropertyDefinition]

    init(
        id: UUID = UUID(),
        name: String,
        propertyDefinitions: [PropertyDefinition] = []
    ) {
        self.id = id
        self.name = name
        self.propertyDefinitions = propertyDefinitions
    }

    static func == (lhs: AssetCategory, rhs: AssetCategory) -> Bool {
        lhs.id == rhs.id
    }
}
