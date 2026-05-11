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

    /// Registers built-in composite *value* types (W × L, W × L × H). Idempotent.
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
