import Foundation

// MARK: - CompositeTypeDefinition

/// A composite *value* type assembled from named fields (e.g. W × L, an Address struct).
/// Distinct from `AssetCategory`, which defines the property template for an `Asset` —
/// `CompositeTypeDefinition` describes the shape of a structured value.
final class CompositeTypeDefinition: Identifiable, Equatable {
    let id: UUID
    var name: String
    var fields: [PropertyDefinition]
    /// Optional compact hint shown after a property's label, e.g. "WxLxHxU".
    /// When empty/nil, no hint is rendered.
    var labelHint: String?

    init(
        id: UUID = UUID(),
        name: String,
        fields: [PropertyDefinition] = [],
        labelHint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fields = fields
        self.labelHint = labelHint
    }

    static func == (lhs: CompositeTypeDefinition, rhs: CompositeTypeDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
