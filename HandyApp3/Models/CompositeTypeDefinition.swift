import Foundation

// MARK: - CompositeTypeDefinition

/// A composite *value* type assembled from named fields (e.g. W × L, an Address struct).
/// Distinct from `AssetCategory`, which defines the property template for an `Asset` —
/// `CompositeTypeDefinition` describes the shape of a structured value.
final class CompositeTypeDefinition: Identifiable, Equatable {
    let id: UUID
    var name: String
    var fields: [PropertyDefinition]

    init(
        id: UUID = UUID(),
        name: String,
        fields: [PropertyDefinition] = []
    ) {
        self.id = id
        self.name = name
        self.fields = fields
    }

    static func == (lhs: CompositeTypeDefinition, rhs: CompositeTypeDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
