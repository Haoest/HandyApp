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
    /// Calls `seedBuiltInComboLists()` first (Range and Cloth Dryer reference Power Source).
    @discardableResult
    func seedBuiltInCategories() -> [AssetCategory] {
        seedBuiltInComboLists()
        var seeded: [AssetCategory] = []

        for (name, defs) in BuiltInTypes.categoryTemplates {
            guard !categories.values.contains(where: { $0.name == name }) else { continue }
            let props = defs.map { AssetProperty(definition: $0) }
            seeded.append(createCategory(name: name, propertyTemplates: props))
        }

        guard let powerSource = comboListDefinitions.values.first(where: { $0.name == "PowerSourceComboList" }) else {
            return seeded
        }
        let applianceTemplates: [AssetCategory] = [
            BuiltInTypes.rangeCategory(powerSource: powerSource),
            BuiltInTypes.clothDryerCategory(powerSource: powerSource),
        ]
        for template in applianceTemplates {
            guard !categories.values.contains(where: { $0.name == template.name }) else { continue }
            seeded.append(createCategory(name: template.name, propertyTemplates: template.propertyTemplates))
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
