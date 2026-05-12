import Foundation

final class AssetFactory {
    func make(name: String, category: AssetCategory) -> Asset {
        let baseProperties = category.propertyTemplates.map {
            AssetProperty(definition: $0.definition, value: $0.value)
        }
        return Asset(name: name, category: category, baseProperties: baseProperties)
    }
}
