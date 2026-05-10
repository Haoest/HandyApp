import Foundation

/// Describes a named, typed property slot. Used as a field on a `CompositeTypeDefinition`
/// or as the schema embedded in an `AssetProperty`.
struct PropertyDefinition: Identifiable, Equatable {
    let id: UUID
    var name: String
    var type: PropertyType
    /// When `false` the field may be omitted from a composite payload without a validation error.
    var isRequired: Bool

    init(id: UUID = UUID(), name: String, type: PropertyType, isRequired: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.isRequired = isRequired
    }
}
