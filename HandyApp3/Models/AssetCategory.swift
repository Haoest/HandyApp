import Foundation

/// A named template that defines the base properties for a class of assets.
/// When an Asset is created from a category, each template entry is deep-copied
/// into the asset's `baseProperties`.
final class AssetCategory: Identifiable, Equatable {
    let id: UUID
    var name: String
    /// The property templates that get stamped onto new assets of this category.
    var propertyTemplates: [AssetProperty]

    init(id: UUID = UUID(), name: String, propertyTemplates: [AssetProperty] = []) {
        self.id = id
        self.name = name
        self.propertyTemplates = propertyTemplates
    }

    static func == (lhs: AssetCategory, rhs: AssetCategory) -> Bool {
        lhs.id == rhs.id
    }
}
