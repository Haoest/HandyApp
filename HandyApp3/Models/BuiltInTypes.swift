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

    /// Seeds a small set of starter assets. Idempotent (skips if name already exists in category).
    @discardableResult
    func seedBuiltInAssets() -> [Asset] {
        let seeds: [(categoryName: String, assetName: String)] = [
            (SystemCategory.residentialHousing.rawValue, "1 main"),
        ]
        var seeded: [Asset] = []
        for seed in seeds {
            guard let cat = categories.values.first(where: { $0.name == seed.categoryName }) else { continue }
            let existing = (try? assets(ofCategoryID: cat.id)) ?? []
            guard !existing.contains(where: { $0.name == seed.assetName }) else { continue }
            if let asset = try? createAsset(name: seed.assetName, categoryID: cat.id) {
                seeded.append(asset)
            }
        }
        return seeded
    }

    /// Seeds an "HVAC" asset under the "1 main" house, with an uncategorized
    /// "air filter" (Notes: filter size) nested under it. Idempotent (skips if an
    /// "HVAC" asset already exists).
    @discardableResult
    func seedSampleHVAC() -> [Asset] {
        guard let house = allAssets.first(where: { $0.name == "1 main" }),
              !allAssets.contains(where: { $0.name == "HVAC" }),
              let hvacCat = categories.values.first(where: { $0.name == SystemCategory.hvac.rawValue }),
              let hvac = try? createAsset(name: "HVAC", categoryID: hvacCat.id) else { return [] }
        try? moveAsset(assetID: hvac.id, toParentID: house.id)
        var seeded = [hvac]
        if let noCat = categories.values.first(where: { $0.name == SystemCategory.noCategory.rawValue }),
           let filter = try? createAsset(name: "air filter", categoryID: noCat.id) {
            try? moveAsset(assetID: filter.id, toParentID: hvac.id)
            if let notesDef = filter.baseProperties.first(where: { $0.definition.name == "Notes" })?.definition {
                try? setPropertyValue(.text("16x25x1"), forDefinitionID: notesDef.id, onAssetID: filter.id)
            }
            seeded.append(filter)
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
            if let cat = try? createCategory(name: key.rawValue, iconName: icon, propertyTemplates: defs.map { AssetProperty(definition: $0) }) {
                seeded.append(cat)
            }
        }
        return seeded
    }

    /// Registers built-in composite *value* types (2D Size, 3D Size). Idempotent.
    @discardableResult
    func seedBuiltInTypes() -> [CompositeTypeDefinition] {
        let templates: [CompositeTypeDefinition] = [
            BuiltInTypes.size2D(),
            BuiltInTypes.size3D(),
        ]
        var seeded: [CompositeTypeDefinition] = []
        for template in templates {
            guard !compositeTypes.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createCompositeType(
                name: template.name,
                fields: template.fields,
                labelHint: template.labelHint
            )
            seeded.append(registered)
        }
        return seeded
    }
}
