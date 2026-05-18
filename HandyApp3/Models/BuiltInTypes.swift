import Foundation

/// Namespace for built-in type factories.
/// Composite *value* types (W × L, W × L × H) live in `SystemTypes/` as extensions on this enum.
enum BuiltInTypes {}

// MARK: - AssetStore seeding

extension AssetStore {

    /// Registers all built-in combo list templates. Idempotent.
    @discardableResult
    func seedBuiltInComboLists() -> [ComboListDefinition] {
        let templates: [ComboListDefinition] = [
            BuiltInTypes.powerSourceComboList(),
        ]
        var seeded: [ComboListDefinition] = []
        for template in templates {
            guard !comboListDefinitions.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createComboList(
                name: template.name,
                systemOptions: template.systemOptions,
                userOptions: template.userOptions,
                isUserExtensible: template.isUserExtensible
            )
            seeded.append(registered)
        }
        return seeded
    }

    /// Registers built-in asset categories. Idempotent.
    @discardableResult
    func seedBuiltInCategories() -> [AssetCategory] {
        var seeded: [AssetCategory] = []
        for (key, defs) in BuiltInTypes.categoryTemplates {
            guard !categories.values.contains(where: { $0.name == key.rawValue }) else { continue }
            let icon = BuiltInTypes.categoryIcons[key] ?? "square.grid.2x2"
            seeded.append(createCategory(name: key.rawValue, iconName: icon, propertyTemplates: defs.map { AssetProperty(definition: $0) }))
        }
        return seeded
    }

    /// Registers built-in composite *value* types (2D Size, 3D Size, Image JPG). Idempotent.
    @discardableResult
    func seedBuiltInTypes() -> [CompositeTypeDefinition] {
        let templates: [CompositeTypeDefinition] = [
            BuiltInTypes.size2D(),
            BuiltInTypes.size3D(),
            BuiltInTypes.imageJPG(),
        ]
        var seeded: [CompositeTypeDefinition] = []
        for template in templates {
            guard !compositeTypes.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createCompositeType(
                name: template.name,
                fields: template.fields
            )
            seeded.append(registered)
        }
        return seeded
    }
}
