import XCTest
@testable import HandyApp3

/// Exercises `StoreMigrator.migrateV5RekeyBuiltInIdentity` — the v4→v5 transform that re-keys
/// built-in categories/fields/composite types/combo lists seeded before commit 49c6600
/// (2026-08-13, when `BuiltInTypes.deterministicID` was introduced) from their random legacy
/// ids onto the canonical deterministic ones. Fixtures use hand-built DTOs with random ids and
/// names matching the canonical built-ins — matching a real pre-49c6600 install, where the
/// exact old id values never mattered, only the names the migration matches on.
final class MigrationV5Tests: XCTestCase {

    // MARK: - DTO builders

    private func basicType(_ t: BasicType) -> PropertyTypeDTO { PropertyTypeDTO(kind: .basic, basicType: t, typeID: nil) }
    private func compositeType(_ id: UUID) -> PropertyTypeDTO { PropertyTypeDTO(kind: .composite, basicType: nil, typeID: id) }
    private func comboType(_ id: UUID) -> PropertyTypeDTO { PropertyTypeDTO(kind: .comboList, basicType: nil, typeID: id) }

    private func makeProp(
        id: UUID = UUID(), name: String, type: PropertyTypeDTO, isRequired: Bool = false,
        value: StoredValueDTO? = nil, sortOrder: Double = 0, modifyDate: Date = Date()
    ) -> AssetPropertyDTO {
        AssetPropertyDTO(
            id: id, definition: PropertyDefinitionDTO(id: UUID(), name: name, type: type, isRequired: isRequired),
            value: value, sortOrder: sortOrder, modifyDate: modifyDate, isDeleted: false, deletedAt: nil
        )
    }

    /// Same as `makeProp` but lets the definition id be pinned explicitly — needed wherever a
    /// test has to make an asset's base property share a template field's `definition.id`.
    private func makeProp(
        id: UUID = UUID(), definitionID: UUID, name: String, type: PropertyTypeDTO, isRequired: Bool = false,
        value: StoredValueDTO? = nil, sortOrder: Double = 0, modifyDate: Date = Date()
    ) -> AssetPropertyDTO {
        AssetPropertyDTO(
            id: id, definition: PropertyDefinitionDTO(id: definitionID, name: name, type: type, isRequired: isRequired),
            value: value, sortOrder: sortOrder, modifyDate: modifyDate, isDeleted: false, deletedAt: nil
        )
    }

    private func makeCategoryDTO(id: UUID = UUID(), name: String, templates: [AssetPropertyDTO] = []) -> CategoryDTO {
        CategoryDTO(id: id, name: name, iconName: "square.grid.2x2",
                    propertyTemplates: templates, isDeleted: false, deletedAt: nil, isPurged: false)
    }

    private func makeAssetDTO(
        id: UUID = UUID(), name: String = "Asset", categoryID: UUID,
        baseProperties: [AssetPropertyDTO] = [], customProperties: [AssetPropertyDTO] = []
    ) -> AssetDTO {
        let now = Date()
        return AssetDTO(
            id: id, name: name, categoryID: categoryID,
            baseProperties: baseProperties, customProperties: customProperties,
            photos: [], events: [], transactions: [],
            parentID: nil, isDeleted: false, deletedAt: nil,
            createdDate: now, modifiedDate: now, parentageModifyDate: now
        )
    }

    private func makeCompositeTypeDTO(id: UUID = UUID(), name: String, fields: [PropertyDefinitionDTO]) -> CompositeTypeDTO {
        CompositeTypeDTO(id: id, name: name, fields: fields, labelHint: nil, modifyDate: Date())
    }

    private func makeComboListDTO(id: UUID = UUID(), name: String, isDeleted: Bool = false) -> ComboListDTO {
        ComboListDTO(id: id, name: name, systemOptions: [], userOptions: [], isUserExtensible: true,
                     modifyDate: Date(), isDeleted: isDeleted, deletedAt: isDeleted ? Date() : nil)
    }

    private func makeSnapshot(
        schemaVersion: Int = 4, compositeTypes: [CompositeTypeDTO] = [], comboLists: [ComboListDTO] = [],
        categories: [CategoryDTO] = [], assets: [AssetDTO] = []
    ) -> StoreSnapshotDTO {
        StoreSnapshotDTO(schemaVersion: schemaVersion, compositeTypes: compositeTypes, comboLists: comboLists,
                         categories: categories, assets: assets, activityLog: [],
                         backgroundTheme: BackgroundTheme.mist.rawValue)
    }

    private func migrate(_ s: StoreSnapshotDTO) -> StoreSnapshotDTO {
        var copy = s
        StoreMigrator.migrateV5RekeyBuiltInIdentity(&copy)
        return copy
    }

    private var applianceCatID: UUID { BuiltInTypes.deterministicID("category.\(SystemCategory.appliance.rawValue)") }
    private var automobileCatID: UUID { BuiltInTypes.deterministicID("category.\(SystemCategory.automobile.rawValue)") }
    private var makeFieldID: UUID { BuiltInTypes.deterministicID("field.automobile.Make") }

    // MARK: - Category + asset categoryID re-key

    func testV5RekeysLegacyCategoryAndAssetCategoryIDs() {
        let legacyCatID = UUID()
        let cat = makeCategoryDTO(id: legacyCatID, name: SystemCategory.appliance.rawValue)
        let asset = makeAssetDTO(categoryID: legacyCatID)

        let result = migrate(makeSnapshot(categories: [cat], assets: [asset]))

        XCTAssertEqual(result.categories[0].id, applianceCatID)
        XCTAssertEqual(result.assets[0].categoryID, applianceCatID)
    }

    // MARK: - Template field + asset base property re-key

    func testV5RekeysTemplateFieldsAndAssetBaseProperties() {
        let legacyDefID = UUID()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let templateField = makeProp(definitionID: legacyDefID, name: "Make", type: basicType(.text), isRequired: true, modifyDate: stamp)
        let cat = makeCategoryDTO(id: automobileCatID, name: SystemCategory.automobile.rawValue, templates: [templateField])
        let baseProp = makeProp(definitionID: legacyDefID, name: "Make", type: basicType(.text), value: .text("Ferrari"), modifyDate: stamp)
        let asset = makeAssetDTO(categoryID: automobileCatID, baseProperties: [baseProp])

        let result = migrate(makeSnapshot(categories: [cat], assets: [asset]))

        let field = result.categories[0].propertyTemplates[0]
        XCTAssertEqual(field.id, makeFieldID)
        XCTAssertEqual(field.definition.id, makeFieldID)

        let prop = result.assets[0].baseProperties[0]
        XCTAssertEqual(prop.id, makeFieldID)
        XCTAssertEqual(prop.definition.id, makeFieldID)
        guard case .text("Ferrari") = prop.value else {
            return XCTFail("only ids change — the stored value must be untouched")
        }
        XCTAssertEqual(prop.modifyDate, stamp, "modifyDate is preserved verbatim for LWW safety")
    }

    // MARK: - Ambiguity / occupancy guards

    func testV5SkipsAmbiguousCategoryName() {
        let a = makeCategoryDTO(name: SystemCategory.appliance.rawValue)
        let b = makeCategoryDTO(name: SystemCategory.appliance.rawValue)

        let result = migrate(makeSnapshot(categories: [a, b]))

        let ids = Set(result.categories.map(\.id))
        XCTAssertEqual(ids, [a.id, b.id], "neither ambiguous candidate is re-keyed")
        XCTAssertFalse(ids.contains(applianceCatID))
    }

    func testV5SkipsWhenCanonicalCategoryIDOccupied() {
        let canonical = makeCategoryDTO(id: applianceCatID, name: SystemCategory.appliance.rawValue)
        let legacyDuplicate = makeCategoryDTO(name: SystemCategory.appliance.rawValue)

        let result = migrate(makeSnapshot(categories: [canonical, legacyDuplicate]))

        XCTAssertTrue(result.categories.contains { $0.id == applianceCatID })
        XCTAssertTrue(result.categories.contains { $0.id == legacyDuplicate.id }, "the occupying duplicate is left untouched, not merged or deleted")
    }

    func testV5SkipsFieldWhenAssetAlreadyHoldsCanonicalDefID() {
        let legacyDefID = UUID()
        let templateField = makeProp(definitionID: legacyDefID, name: "Make", type: basicType(.text))
        let cat = makeCategoryDTO(id: automobileCatID, name: SystemCategory.automobile.rawValue, templates: [templateField])

        let assetA = makeAssetDTO(name: "A", categoryID: automobileCatID,
                                  baseProperties: [makeProp(definitionID: legacyDefID, name: "Make", type: basicType(.text), value: .text("Toyota"))])
        let blockingCustom = makeProp(id: makeFieldID, definitionID: makeFieldID, name: "Make (custom)", type: basicType(.text))
        let assetB = makeAssetDTO(name: "B", categoryID: automobileCatID,
                                  baseProperties: [makeProp(definitionID: legacyDefID, name: "Make", type: basicType(.text), value: .text("Honda"))],
                                  customProperties: [blockingCustom])

        let result = migrate(makeSnapshot(categories: [cat], assets: [assetA, assetB]))

        // Template-level re-key still happens regardless of any individual asset's state.
        XCTAssertEqual(result.categories[0].propertyTemplates[0].definition.id, makeFieldID)

        let resultA = result.assets.first { $0.name == "A" }!
        XCTAssertEqual(resultA.baseProperties[0].definition.id, makeFieldID, "asset A had no conflict, so it re-keys")

        let resultB = result.assets.first { $0.name == "B" }!
        XCTAssertEqual(resultB.baseProperties[0].definition.id, legacyDefID, "asset B already holds the canonical id via a custom property — its base property must not be duplicated onto it")
    }

    // MARK: - Composite type re-key + typeID reference rewrite

    func testV5RekeysCompositeTypeAndRewritesAllTypeIDReferences() {
        let legacyCompositeID = UUID()
        let fields = [
            PropertyDefinitionDTO(id: UUID(), name: "Width", type: basicType(.number), isRequired: true),
            PropertyDefinitionDTO(id: UUID(), name: "Length", type: basicType(.number), isRequired: true),
            PropertyDefinitionDTO(id: UUID(), name: "Height", type: basicType(.number), isRequired: true),
            PropertyDefinitionDTO(id: UUID(), name: "Unit", type: basicType(.text), isRequired: false),
        ]
        let composite = makeCompositeTypeDTO(id: legacyCompositeID, name: "3D Size", fields: fields)

        let templateField = makeProp(name: "Size", type: compositeType(legacyCompositeID))
        let cat = makeCategoryDTO(id: applianceCatID, name: SystemCategory.appliance.rawValue, templates: [templateField])

        let baseProp = makeProp(name: "Size", type: compositeType(legacyCompositeID))
        let customProp = makeProp(name: "Box Size", type: compositeType(legacyCompositeID))
        let asset = makeAssetDTO(categoryID: applianceCatID, baseProperties: [baseProp], customProperties: [customProp])

        let result = migrate(makeSnapshot(compositeTypes: [composite], categories: [cat], assets: [asset]))

        let canonicalID = BuiltInTypes.deterministicID("compositeType.3DSize")
        XCTAssertEqual(result.compositeTypes[0].id, canonicalID)
        for field in result.compositeTypes[0].fields {
            XCTAssertEqual(field.id, BuiltInTypes.deterministicID("compositeType.3DSize.\(field.name)"))
        }
        XCTAssertEqual(result.categories[0].propertyTemplates[0].definition.type.typeID, canonicalID)
        XCTAssertEqual(result.assets[0].baseProperties[0].definition.type.typeID, canonicalID)
        XCTAssertEqual(result.assets[0].customProperties[0].definition.type.typeID, canonicalID)
    }

    // MARK: - Combo list re-key + stray reference repointing

    func testV5RekeysComboListAndRepointsSoftDeletedStrayReferences() {
        let legacyRetailerID = UUID()
        let strayID = UUID()
        let legacy = makeComboListDTO(id: legacyRetailerID, name: "Retailer", isDeleted: false)
        let stray = makeComboListDTO(id: strayID, name: "Retailer", isDeleted: true)

        let templateField = makeProp(name: "Retailer", type: comboType(strayID))
        let cat = makeCategoryDTO(id: applianceCatID, name: SystemCategory.appliance.rawValue, templates: [templateField])

        let result = migrate(makeSnapshot(comboLists: [legacy, stray], categories: [cat]))

        let canonicalID = BuiltInTypes.deterministicID("comboList.retailer")
        XCTAssertTrue(result.comboLists.contains { $0.id == canonicalID }, "the live legacy list re-keys onto the canonical id")
        XCTAssertTrue(result.comboLists.contains { $0.id == strayID && ($0.isDeleted ?? false) }, "the soft-deleted stray record itself is left in place — absence never deletes")
        XCTAssertEqual(result.categories[0].propertyTemplates[0].definition.type.typeID, canonicalID,
                       "a reference to the stray's old id is repointed to the canonical id, not left dangling")
    }

    // MARK: - Idempotency

    func testV5IsIdempotent() {
        let legacyCompositeID = UUID()
        let composite = makeCompositeTypeDTO(id: legacyCompositeID, name: "3D Size", fields: [
            PropertyDefinitionDTO(id: UUID(), name: "Width", type: basicType(.number), isRequired: true),
        ])
        let legacyComboID = UUID()
        let comboList = makeComboListDTO(id: legacyComboID, name: "Retailer")
        let legacyDefID = UUID()
        let templateField = makeProp(definitionID: legacyDefID, name: "Make", type: basicType(.text))
        let sizeField = makeProp(name: "Size", type: compositeType(legacyCompositeID))
        let retailerField = makeProp(name: "Retailer", type: comboType(legacyComboID))
        let cat = makeCategoryDTO(id: automobileCatID, name: SystemCategory.automobile.rawValue,
                                  templates: [templateField, sizeField, retailerField])
        let asset = makeAssetDTO(categoryID: automobileCatID,
                                 baseProperties: [makeProp(definitionID: legacyDefID, name: "Make", type: basicType(.text), value: .text("Ferrari"))])

        let once = migrate(makeSnapshot(compositeTypes: [composite], comboLists: [comboList], categories: [cat], assets: [asset]))
        var twice = once
        StoreMigrator.migrateV5RekeyBuiltInIdentity(&twice)

        let encoder = CanonicalCodec.makeEncoder()
        XCTAssertEqual(try encoder.encode(once.canonicalized()), try encoder.encode(twice.canonicalized()))
    }

    // MARK: - Integration: migration unblocks the existing upgrade pass

    func testV5ThenUpgradeBringsLegacyInstallCurrent() throws {
        let legacyDefID = UUID()
        let oldTextRetailer = makeProp(definitionID: legacyDefID, name: "Retailer", type: basicType(.text))
        let cat = makeCategoryDTO(name: SystemCategory.appliance.rawValue, templates: [oldTextRetailer])
        let asset = makeAssetDTO(name: "Dryer", categoryID: cat.id,
                                 baseProperties: [makeProp(definitionID: legacyDefID, name: "Retailer", type: basicType(.text), value: .text("Home Depot"))])
        let snap = makeSnapshot(schemaVersion: 4, categories: [cat], assets: [asset])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        _ = StoreFileLayout().write(snap, baseDir: tempDir)

        AssetStore.baseDirOverride = tempDir
        defer { AssetStore.baseDirOverride = nil }
        let store = AssetStore()
        XCTAssertTrue(store.load())

        store.seedBuiltInComboLists()
        store.seedBuiltInCategories()
        let changed = store.upgradeBuiltInCategories()
        store.seedBuiltInTypes()

        XCTAssertGreaterThan(changed, 0, "the migration must make the legacy category reachable by id, so upgrade actually does work")
        XCTAssertEqual(store.categories.values.filter { $0.name == SystemCategory.appliance.rawValue }.count, 1,
                       "no duplicate Appliance category")

        let liveCat = try XCTUnwrap(store.categories[applianceCatID])
        let retailerTemplate = try XCTUnwrap(liveCat.propertyTemplates.first { $0.definition.name == "Retailer" && !$0.isDeleted })
        guard case .comboList = retailerTemplate.definition.type else {
            return XCTFail("upgrade should have refreshed the re-keyed field to the canonical combo-list type")
        }

        let liveAsset = try XCTUnwrap(store.allAssets.first { $0.name == "Dryer" })
        let baseProp = try XCTUnwrap(liveAsset.baseProperties.first { $0.definition.name == "Retailer" })
        XCTAssertEqual(baseProp.value, .text("Home Depot"), "the asset's own value is untouched by both migration and the template-only upgrade pass")
    }

    // MARK: - importJSON of a legacy-shaped export

    func testImportOfLegacyExportMergesWithoutDuplicates() throws {
        AssetStore.baseDirOverride = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { AssetStore.baseDirOverride = nil }
        let store = AssetStore()
        try store.createCategory(id: applianceCatID, name: SystemCategory.appliance.rawValue)

        let legacyCat = makeCategoryDTO(name: SystemCategory.appliance.rawValue)
        let legacyAsset = makeAssetDTO(name: "Legacy Fridge", categoryID: legacyCat.id)
        let legacySnapshot = makeSnapshot(schemaVersion: 4, categories: [legacyCat], assets: [legacyAsset])
        let data = try XCTUnwrap(CanonicalCodec.encode(legacySnapshot))

        try store.importJSON(data: data)

        XCTAssertEqual(store.categories.values.filter { $0.name == SystemCategory.appliance.rawValue }.count, 1,
                       "the imported legacy category re-keys onto the same canonical id already live locally, instead of duplicating")
        let importedAsset = try XCTUnwrap(store.allAssets.first { $0.name == "Legacy Fridge" })
        XCTAssertEqual(importedAsset.category.id, applianceCatID)
    }
}
