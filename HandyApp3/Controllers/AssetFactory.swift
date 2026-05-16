import Foundation

final class AssetFactory {
    func make(name: String, category: AssetCategory) -> Asset {
        let baseProperties = category.propertyTemplates.enumerated().map { index, template in
            AssetProperty(definition: template.definition, value: template.value,
                          sortOrder: Double(index) * AssetProperty.sortOrderIncrement)
        }
        return Asset(name: name, category: category, baseProperties: baseProperties)
    }
}
