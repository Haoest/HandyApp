import Foundation
import UIKit

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
            (SystemCategory.appliance.rawValue,          "Fridge"),
            (SystemCategory.automobile.rawValue,         "2006 toyota"),
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

    /// Seeds sample events on the "1 main" house: 2 recurring + 12 non-recurring —
    /// enough to exercise the capped detail list and its "…" overflow row.
    /// Idempotent (skips if the asset already has events).
    @discardableResult
    func seedSampleEvents() -> [Event] {
        guard let house = allAssets.first(where: { $0.name == "1 main" }),
              house.events.isEmpty else { return [] }
        let calendar = Calendar.current
        var seeded: [Event] = []
        func add(_ title: String, monthsAgo: Int, recurrence: RecurrenceInterval? = nil) {
            let date = calendar.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
            if let event = try? addEvent(title: title, date: date, recurrence: recurrence, toAssetID: house.id) {
                seeded.append(event)
            }
        }
        add("Furnace filter replacement", monthsAgo: 1, recurrence: .monthly)
        add("Property tax payment", monthsAgo: 2, recurrence: .annually)
        for i in 1...12 {
            add("Sample event \(i)", monthsAgo: i)
        }
        return seeded
    }

    /// Seeds sample transactions on the "Fridge" appliance: 2 recurring +
    /// 12 non-recurring — enough to exercise the capped detail list and its "…"
    /// overflow row. Idempotent (skips if the asset already has transactions).
    @discardableResult
    func seedSampleTransactions() -> [Transaction] {
        guard let fridge = allAssets.first(where: { $0.name == "Fridge" }),
              fridge.transactions.isEmpty else { return [] }
        let calendar = Calendar.current
        var seeded: [Transaction] = []
        func add(_ details: String, amount: Decimal, monthsAgo: Int, recurrence: RecurrenceInterval? = nil) {
            let date = calendar.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
            if let txn = try? addTransaction(details: details, amount: amount, date: date, kind: .expense, recurrence: recurrence, toAssetID: fridge.id) {
                seeded.append(txn)
            }
        }
        add("Water filter subscription", amount: 35, monthsAgo: 1, recurrence: .quarterly)
        add("Extended warranty premium", amount: 120, monthsAgo: 2, recurrence: .annually)
        for i in 1...12 {
            add("Sample transaction \(i)", amount: Decimal(i * 10), monthsAgo: i)
        }
        return seeded
    }

    /// Seeds the bundled SeedFiles photos onto the "1 main" house, scaled the same way
    /// user-added photos are. Idempotent (skips if the house already has photos).
    @discardableResult
    func seedSamplePhotos() -> [Photo] {
        guard let house = allAssets.first(where: { $0.name == "1 main" }),
              house.photos.isEmpty else { return [] }
        // SeedFiles images are flattened into the bundle root at build time, so enumerate
        // by extension and seed in a stable order rather than hard-coding file names.
        let urls = ["jpg", "jpeg", "png"]
            .flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var seeded: [Photo] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data),
                  let imageData = ImageScaling.imageData(from: image),
                  let thumbData = ImageScaling.thumbnailData(from: image),
                  let photo = try? addPhoto(imageData: imageData, thumbnailData: thumbData, toAssetID: house.id)
            else { continue }
            seeded.append(photo)
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
