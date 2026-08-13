import Foundation
import CryptoKit

/// Namespace for built-in type factories.
/// Composite *value* types (W × L, W × L × H) live in `SystemTypes/` as extensions on this enum.
enum BuiltInTypes {
    /// Deterministic id for a built-in construct (composite type, combo list, category, or
    /// template field), stable across launches and devices. Two devices that each seed the
    /// same built-in offline, before ever syncing, must agree on its id — otherwise merging
    /// their stores later duplicates it instead of recognizing it as the same record. Keyed
    /// by a stable identifier, never the display name alone, so a future rename doesn't
    /// reassign the id.
    static func deterministicID(_ key: String) -> UUID {
        let digest = SHA256.hash(data: Data("HandyApp3.BuiltIn.\(key)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

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
                id: template.id,
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
            (SystemCategory.residentialHousing.rawValue, "My Home"),
            (SystemCategory.automobile.rawValue,         "Testarossa 85"),
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

    /// Fills in the "Testarossa 85" automobile's field values and a "Paint Color"
    /// custom property. Idempotent (skips if Make is already set).
    @discardableResult
    func seedSampleAutomobile() -> Asset? {
        guard let car = allAssets.first(where: { $0.name == "Testarossa 85" }),
              car.baseProperties.first(where: { $0.definition.name == "Make" })?.value == nil else { return nil }
        func setBase(_ name: String, _ value: StoredValue) {
            if let def = car.baseProperties.first(where: { $0.definition.name == name })?.definition {
                try? setPropertyValue(value, forDefinitionID: def.id, onAssetID: car.id)
            }
        }
        setBase("Make", .text("Ferrari"))
        setBase("Model", .text("Testarossa"))
        setBase("Year", .number(1985))
        setBase("License Plate", .text("FASTEST"))
        setBase("Engine Oil", .text("10W-40"))
        try? addCustomProperty(
            definition: PropertyDefinition(name: "Paint Color", type: .basic(.text), isRequired: false),
            value: .text("Rossi Corsa"),
            toAssetID: car.id
        )
        return car
    }

    /// Registers built-in asset categories. Idempotent.
    @discardableResult
    func seedBuiltInCategories() -> [AssetCategory] {
        var seeded: [AssetCategory] = []
        for (key, defs) in BuiltInTypes.categoryTemplates {
            guard !categories.values.contains(where: { $0.name == key.rawValue }) else { continue }
            let icon = BuiltInTypes.categoryIcons[key] ?? "square.grid.2x2"
            let categoryID = BuiltInTypes.deterministicID("category.\(key.rawValue)")
            // AssetProperty.id mirrors its definition's id — the two are 1:1 for a
            // freshly-seeded template, and the reconciler's template merge keys on
            // AssetProperty.id, so this keeps a rename or field edit converging as
            // one record instead of duplicating it across devices.
            let templates = defs.map { AssetProperty(id: $0.id, definition: $0) }
            if let cat = try? createCategory(id: categoryID, name: key.rawValue, iconName: icon, propertyTemplates: templates) {
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
                id: template.id,
                name: template.name,
                fields: template.fields,
                labelHint: template.labelHint
            )
            seeded.append(registered)
        }
        return seeded
    }
}
