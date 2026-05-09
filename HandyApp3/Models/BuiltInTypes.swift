import Foundation

/// Namespace for built-in type factories.
/// Composite *value* types (W × L, W × L × H) live in `SystemTypes/` as extensions on this enum.
/// Built-in IS-A type nodes (Appliance/Range/etc.) are seeded by `AssetStore.seedBuiltInTypeTree()`.
enum BuiltInTypes {}

// MARK: - AssetStore seeding

extension AssetStore {

    /// Registers all built-in combo list templates.
    /// Idempotent — skips any list whose name already exists in the store.
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

    /// Registers built-in composite *value* types (W × L, W × L × H).
    /// IS-A type nodes are seeded separately via `seedBuiltInTypeTree()`.
    /// Idempotent — skips any template whose name already exists.
    @discardableResult
    func seedBuiltInTypes(scope: CompositeTypeScope = .global) -> [CompositeTypeDefinition] {
        let templates: [CompositeTypeDefinition] = [
            BuiltInTypes.widthByLength(scope: scope),
            BuiltInTypes.widthByLengthByHeight(scope: scope),
        ]
        var seeded: [CompositeTypeDefinition] = []
        for template in templates {
            guard !compositeTypes.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createCompositeType(
                name: template.name,
                systemFields: template.systemFields,
                userFields: template.userFields,
                isUserExtensible: template.isUserExtensible,
                scope: template.scope
            )
            seeded.append(registered)
        }
        return seeded
    }
}
