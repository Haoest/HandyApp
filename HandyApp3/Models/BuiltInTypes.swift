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

    /// Registers all built-in combo list templates. Idempotent, keyed by the template's
    /// deterministic id rather than its name: a name-keyed guard would treat a user's rename of
    /// a built-in list as "not seeded yet" and re-seed a duplicate under the original id on the
    /// next launch, silently reverting the rename and wiping any options accumulated since.
    /// Presence-keyed, not liveness-keyed: a soft-deleted built-in list is still present in
    /// `comboListDefinitions` (see `AssetStore.allComboListDefinitions`), so the guard finds it
    /// and skips — a deliberate delete is not resurrected by the seeder.
    ///
    /// Also self-heals installs left with a stray duplicate of a built-in under some other id —
    /// e.g. an install that seeded this list back when this guard was still name-keyed and
    /// somehow ended up with it under a non-deterministic id, or a name freed up by soft-
    /// deleting the original and later reused by a hand-created replacement. See
    /// `resolveBuiltInComboList(for:)`.
    @discardableResult
    func seedBuiltInComboLists() -> [ComboListDefinition] {
        let templates: [ComboListDefinition] = [
            BuiltInTypes.powerSourceComboList(),
            BuiltInTypes.retailerComboList(),
            BuiltInTypes.applianceTypeComboList(),
        ]
        return templates.compactMap { resolveBuiltInComboList(for: $0) }
    }

    /// Ensures exactly one live combo list represents `template`, at its deterministic id, and
    /// folds in any stray duplicate sharing its name under a different id. Returns the record
    /// only when this call newly created or updated the canonical one — a plain "already
    /// present, nothing to do" skip returns `nil`, matching `seedBuiltInComboLists`'s old
    /// `seeded`-array bookkeeping.
    private func resolveBuiltInComboList(for template: ComboListDefinition) -> ComboListDefinition? {
        let strays = allComboListDefinitions.filter {
            $0.id != template.id && $0.name.caseInsensitiveCompare(template.name) == .orderedSame
        }
        guard !strays.isEmpty else {
            guard comboListDefinitions[template.id] == nil else { return nil }
            return createComboList(
                id: template.id, name: template.name,
                systemOptions: template.systemOptions, userOptions: template.userOptions,
                isUserExtensible: template.isUserExtensible
            )
        }

        // `ComboListDefinition.id` is `let`, so a stray can't be relabeled onto the
        // deterministic id — fold its accumulated options into whichever record ends up there
        // and soft-delete the stray (recoverable in Trash, not silently discarded).
        let strayOptions = strays.flatMap(\.allOptions)
        for stray in strays { try? softDeleteComboList(id: stray.id) }

        if let existing = comboListDefinitions[template.id] {
            // Presence-keyed, not liveness-keyed, same as the simple path above: a deliberately
            // soft-deleted built-in must not be resurrected just because a stray turned up.
            guard !existing.isDeleted else { return nil }
            for option in strayOptions where !existing.allOptions.contains(option) {
                existing.userOptions.append(option)
            }
            existing.modifyDate = Date()
            markDirty()
            return nil
        }
        let carriedOptions = strayOptions.filter {
            !template.systemOptions.contains($0) && !template.userOptions.contains($0)
        }
        return createComboList(
            id: template.id, name: template.name,
            systemOptions: template.systemOptions, userOptions: template.userOptions + carriedOptions,
            isUserExtensible: template.isUserExtensible
        )
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

    /// Upgrade phase, run after `seedBuiltInCategories`: merges canonical `categoryTemplates`
    /// changes into categories an install already seeded before the change shipped — e.g.
    /// Appliance's "Retailer" field moving from free text to a combo list. Without this pass,
    /// `seedBuiltInCategories`'s "create if the category doesn't exist yet" guard would leave
    /// an existing install stuck on whatever template shape it first seeded.
    ///
    /// Matches both the category and each field by deterministic id, same as
    /// `seedBuiltInCategories`, so a user rename doesn't read as "missing" and re-add. A field
    /// the user tombstoned (`removeTemplateProperty`) is left alone rather than resurrected or
    /// edited — same presence-keyed-not-liveness-keyed rule `resolveBuiltInComboList` uses for
    /// combo lists. Categories the user deleted or that were purged are skipped entirely.
    ///
    /// Retirement is a separate first pass: `BuiltInTypes.retiredFieldIDs` tombstones a field
    /// outright rather than mutating its type in place, so its replacement (a different id in
    /// `categoryTemplates`) comes in clean through the normal "missing canonical field" pass
    /// below instead of inheriting the old field's stored value or history.
    @discardableResult
    func upgradeBuiltInCategories() -> Int {
        var changed = 0
        for (key, retiredIDs) in BuiltInTypes.retiredFieldIDs {
            let categoryID = BuiltInTypes.deterministicID("category.\(key.rawValue)")
            guard let cat = categories[categoryID], !cat.isDeleted, !cat.isPurged else { continue }
            for retiredID in retiredIDs {
                guard let prop = cat.propertyTemplates.first(where: { $0.id == retiredID }), !prop.isDeleted else { continue }
                try? removeTemplateProperty(id: retiredID, fromCategoryID: cat.id)
                changed += 1
            }
        }
        for (key, defs) in BuiltInTypes.categoryTemplates {
            let categoryID = BuiltInTypes.deterministicID("category.\(key.rawValue)")
            guard let cat = categories[categoryID], !cat.isDeleted, !cat.isPurged else { continue }
            for def in defs {
                if let existing = cat.propertyTemplates.first(where: { $0.id == def.id }) {
                    guard !existing.isDeleted, existing.definition != def else { continue }
                    try? updateTemplateProperty(
                        id: def.id, inCategoryID: cat.id,
                        name: def.name, type: def.type, isRequired: def.isRequired
                    )
                    changed += 1
                } else {
                    try? addTemplateProperty(AssetProperty(id: def.id, definition: def), toCategoryID: cat.id)
                    changed += 1
                }
            }
        }
        return changed
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
