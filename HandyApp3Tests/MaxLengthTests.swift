import XCTest
@testable import HandyApp3

final class MaxLengthTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    // MARK: - PropertyDefinition.clamped

    func testClampedPassesThroughUnderOrAtBound() {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), maxLength: 5)
        XCTAssertEqual(def.clamped("abc"), "abc")
        XCTAssertEqual(def.clamped("abcde"), "abcde")
    }

    func testClampedTruncatesOverBound() {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), maxLength: 5)
        XCTAssertEqual(def.clamped("abcdefgh"), "abcde")
    }

    func testClampedIsPassThroughWhenBoundIsNil() {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), maxLength: nil)
        XCTAssertEqual(def.clamped(String(repeating: "x", count: 500)), String(repeating: "x", count: 500))
    }

    func testClampedCountsGraphemeClustersNotUTF16Units() {
        // A family emoji is one Character but several UTF-16 code units — clamping must not
        // split it, and must count it as exactly 1 toward the bound.
        let def = PropertyDefinition(name: "Field", type: .basic(.text), maxLength: 1)
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(def.clamped(family), family)
    }

    func testAcceptsMaxLengthOnlyForTextAndComboList() {
        XCTAssertTrue(PropertyDefinition(name: "A", type: .basic(.text)).acceptsMaxLength)
        let list = ComboListDefinition(name: "List", userOptions: ["A"])
        XCTAssertTrue(PropertyDefinition(name: "B", type: .comboList(list)).acceptsMaxLength)
        XCTAssertFalse(PropertyDefinition(name: "C", type: .basic(.number)).acceptsMaxLength)
        XCTAssertFalse(PropertyDefinition(name: "D", type: .basic(.date)).acceptsMaxLength)
        XCTAssertFalse(PropertyDefinition(name: "E", type: .basic(.contact)).acceptsMaxLength)
    }

    // MARK: - Store clamp invariant

    func testSetTemplatePropertyValueClampsOverLongText() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 5)
        let prop = AssetProperty(definition: def)
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [prop])

        try store.setTemplatePropertyValue(.text("abcdefgh"), forPropertyID: prop.id, inCategoryID: cat.id)

        XCTAssertEqual(prop.value, .text("abcde"))
    }

    func testSetPropertyValueClampsOverLongTextOnBaseProperty() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 4)
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [AssetProperty(definition: def)])
        let asset = try store.createAsset(name: "Asset", categoryID: cat.id)
        let baseDef = try XCTUnwrap(asset.baseProperties.first).definition

        try store.setPropertyValue(.text("abcdefgh"), forDefinitionID: baseDef.id, onAssetID: asset.id)

        XCTAssertEqual(asset.value(for: baseDef.id), .text("abcd"))
    }

    func testAddCustomPropertyClampsInitialValue() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let def = PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false, maxLength: 3)

        let prop = try store.addCustomProperty(definition: def, value: .text("abcdef"), toAssetID: asset.id)

        XCTAssertEqual(prop.value, .text("abc"))
    }

    func testSetCustomPropertyValueClampsOverLongText() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let def = PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false, maxLength: 3)
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        try store.setCustomPropertyValue(.text("abcdef"), forCustomPropertyID: prop.id, onAssetID: asset.id)

        XCTAssertEqual(prop.value, .text("abc"))
    }

    func testComboListAutoAddRecordsClampedOption() throws {
        let list = ComboListDefinition(name: "List", isUserExtensible: true)
        let def = PropertyDefinition(name: "Field", type: .comboList(list), isRequired: false, maxLength: 4)
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        try store.setCustomPropertyValue(.text("abcdefgh"), forCustomPropertyID: prop.id, onAssetID: asset.id)

        XCTAssertEqual(list.userOptions, ["abcd"], "the auto-added option must be the clamped value, not the raw one")
    }

    func testCompositeSubFieldsClampIndependently() throws {
        let unitField = PropertyDefinition(name: "Unit", type: .basic(.text), isRequired: false, maxLength: 2)
        let composite = CompositeTypeDefinition(name: "Size", fields: [
            PropertyDefinition(name: "Width", type: .basic(.number), isRequired: true),
            unitField,
        ])
        let def = PropertyDefinition(name: "Size", type: .composite(composite), isRequired: false)
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        try store.setCustomPropertyValue(
            .composite(["Width": .number(3), "Unit": .text("meters")]),
            forCustomPropertyID: prop.id, onAssetID: asset.id
        )

        guard case .composite(let payload) = prop.value else { return XCTFail("expected composite value") }
        XCTAssertEqual(payload["Width"], .number(3), "an unbounded sub-field is untouched")
        XCTAssertEqual(payload["Unit"], .text("me"), "the bounded sub-field is clamped to its own field's maxLength")
    }

    // MARK: - updateTemplateProperty value-clearing guard

    func testUnchangedTypePassedToUpdateTemplatePropertyKeepsValue() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 20)
        let prop = AssetProperty(definition: def, value: .text("kept"))
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [prop])

        try store.updateTemplateProperty(id: prop.id, inCategoryID: cat.id, name: "Field", type: .basic(.text), isRequired: false, maxLength: 20)

        XCTAssertEqual(prop.value, .text("kept"), "passing the same type must not clear the value")
    }

    func testGenuinelyDifferentTypePassedToUpdateTemplatePropertyClearsValue() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 20)
        let prop = AssetProperty(definition: def, value: .text("kept"))
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [prop])

        try store.updateTemplateProperty(id: prop.id, inCategoryID: cat.id, type: .basic(.number))

        XCTAssertNil(prop.value, "a real type change must still clear the now-invalid value")
    }

    // MARK: - System-wide max length ceiling

    func testAppendTemplatePropertyCapsMaxLengthAtSystemMax() throws {
        let cat = try store.createCategory(name: "Cat")
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 999_999)

        let prop = try store.appendTemplateProperty(definition: def, toCategoryID: cat.id)

        XCTAssertEqual(prop.definition.maxLength, PropertyDefinition.systemMaxLength)
    }

    func testAddCustomPropertyCapsMaxLengthAtSystemMax() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 999_999)

        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        XCTAssertEqual(prop.definition.maxLength, PropertyDefinition.systemMaxLength)
    }

    func testUpdateTemplatePropertyCapsMaxLengthAtSystemMax() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 20)
        let prop = AssetProperty(definition: def)
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [prop])

        try store.updateTemplateProperty(id: prop.id, inCategoryID: cat.id, maxLength: 999_999)

        XCTAssertEqual(prop.definition.maxLength, PropertyDefinition.systemMaxLength)
    }

    func testUpdateCustomPropertyCapsMaxLengthAtSystemMax() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let prop = try store.addCustomProperty(definition: PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 20), toAssetID: asset.id)

        try store.updateCustomProperty(id: prop.id, onAssetID: asset.id, maxLength: 999_999)

        XCTAssertEqual(prop.definition.maxLength, PropertyDefinition.systemMaxLength)
    }

    func testCreateCategoryCapsTemplateMaxLengthAtSystemMax() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 999_999)
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [AssetProperty(definition: def)])

        XCTAssertEqual(cat.propertyTemplates.first?.definition.maxLength, PropertyDefinition.systemMaxLength)
    }

    // MARK: - Persistence round trip

    func testMaxLengthSurvivesDTORoundTrip() throws {
        let dto = PropertyDefinitionDTO(id: UUID(), name: "Field", type: PropertyTypeDTO(kind: .basic, basicType: .text, typeID: nil), isRequired: false, maxLength: 42)
        let encoder = CanonicalCodec.makeEncoder()
        let data = try encoder.encode(dto)
        let decoded = try CanonicalCodec.makeDecoder().decode(PropertyDefinitionDTO.self, from: data)
        XCTAssertEqual(decoded.maxLength, 42)
    }

    func testMaxLengthDecodesToNilWhenKeyIsAbsent() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Field","type":{"kind":"basic","basicType":"text"},"isRequired":false}
        """
        let decoded = try CanonicalCodec.makeDecoder().decode(PropertyDefinitionDTO.self, from: Data(json.utf8))
        XCTAssertNil(decoded.maxLength, "a shard written before this field existed must still decode, with a nil bound")
    }

    func testMaxLengthSurvivesFullStoreSaveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir
        defer {
            AssetStore.baseDirOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 77)
        _ = try store.createCategory(name: "Cat", propertyTemplates: [AssetProperty(definition: def)])
        store.save()

        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())
        let reloadedProp = try XCTUnwrap(reloaded.allCategories.first?.propertyTemplates.first)
        XCTAssertEqual(reloadedProp.definition.maxLength, 77)
    }

    // MARK: - upgradeBuiltInCategories forwards maxLength

    func testUpgradeBuiltInCategoriesStampsMissingBoundOntoExistingInstall() throws {
        let categoryID = BuiltInTypes.deterministicID("category.\(SystemCategory.automobile.rawValue)")
        let makeFieldID = BuiltInTypes.deterministicID("field.automobile.Make")
        // Simulates a pre-feature install: same id, same name/type, but no bound yet.
        let staleMake = AssetProperty(id: makeFieldID, definition: PropertyDefinition(id: makeFieldID, name: "Make", type: .basic(.text), isRequired: true, maxLength: nil))
        let cat = try store.createCategory(id: categoryID, name: SystemCategory.automobile.rawValue, propertyTemplates: [staleMake])

        let changed = store.upgradeBuiltInCategories()
        XCTAssertGreaterThan(changed, 0)
        let upgraded = try XCTUnwrap(cat.propertyTemplates.first { $0.id == makeFieldID })
        XCTAssertEqual(upgraded.definition.maxLength, 40)

        let secondPassChanged = store.upgradeBuiltInCategories()
        XCTAssertEqual(secondPassChanged, 0, "a second upgrade pass must find nothing left to do")
    }

    // MARK: - backfillMissingMaxLengths

    func testBackfillFillsFromMatchingCategoryTemplate() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: nil)
        let template = AssetProperty(definition: def)
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [template])
        let asset = try store.createAsset(name: "Asset", categoryID: cat.id)
        // Give the template a bound *after* the asset copied it, mirroring an
        // `upgradeBuiltInCategories` pass that ran before the backfill.
        template.definition.maxLength = 30

        let changed = store.backfillMissingMaxLengths()

        XCTAssertGreaterThan(changed, 0)
        let assetProp = try XCTUnwrap(asset.baseProperties.first)
        XCTAssertEqual(assetProp.definition.maxLength, 30, "an asset's own copy should converge on its template's bound, not the generic default")
    }

    func testBackfillFallsBackToDefaultForOrphanCustomProperty() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let def = PropertyDefinition(name: "Custom", type: .basic(.text), isRequired: false, maxLength: nil)
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        let changed = store.backfillMissingMaxLengths()

        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(prop.definition.maxLength, PropertyDefinition.defaultTextMaxLength)
    }

    func testBackfillNeverOverwritesAnExistingBound() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let def = PropertyDefinition(name: "Custom", type: .basic(.text), isRequired: false, maxLength: 9)
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        _ = store.backfillMissingMaxLengths()

        XCTAssertEqual(prop.definition.maxLength, 9)
    }

    func testBackfillNeverTruncatesAnAlreadyStoredValue() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        // Bypasses the store's own clamp-on-write to simulate data that predates the bound.
        let def = PropertyDefinition(name: "Custom", type: .basic(.text), isRequired: false, maxLength: nil)
        let prop = try store.addCustomProperty(definition: def, value: .text("a very long pre-existing value"), toAssetID: asset.id)

        _ = store.backfillMissingMaxLengths()

        XCTAssertEqual(prop.value, .text("a very long pre-existing value"), "backfill fills the bound going forward; it must not retroactively clamp what's already stored")
    }

    func testBackfillIsIdempotent() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        _ = try store.addCustomProperty(definition: PropertyDefinition(name: "Custom", type: .basic(.text), isRequired: false), toAssetID: asset.id)

        XCTAssertGreaterThan(store.backfillMissingMaxLengths(), 0)
        XCTAssertEqual(store.backfillMissingMaxLengths(), 0)
    }

    func testBackfillFillsCompositeUnitFieldFromShippedFactory() throws {
        _ = store.seedBuiltInTypes()
        let size3D = try XCTUnwrap(store.allCompositeTypes.first { $0.name == "3D Size" })
        let unitIdx = try XCTUnwrap(size3D.fields.firstIndex { $0.name == "Unit" })
        size3D.fields[unitIdx].maxLength = nil // simulate a pre-feature install

        _ = store.backfillMissingMaxLengths()

        XCTAssertEqual(size3D.fields[unitIdx].maxLength, 12)
    }

    // MARK: - propagateTemplates

    func testMaxLengthOnlyChangeCountsAsRefreshedNotValuesCleared() throws {
        let def = PropertyDefinition(name: "Field", type: .basic(.text), isRequired: false, maxLength: 100)
        let template = AssetProperty(definition: def, sortOrder: 0)
        let cat = try store.createCategory(name: "Cat", propertyTemplates: [template])
        let asset = try store.createAsset(name: "Asset", categoryID: cat.id)
        try store.setPropertyValue(.text("short"), forDefinitionID: def.id, onAssetID: asset.id)

        // Tighten the bound on the template only — same name, same type, same isRequired.
        try store.updateTemplateProperty(id: template.id, inCategoryID: cat.id, maxLength: 3)

        let summary = try store.propagateTemplates(forCategoryID: cat.id)

        XCTAssertEqual(summary.refreshed, 1)
        XCTAssertEqual(summary.valuesCleared, 0, "a still-valid (if now over-bound) value is not the 'no longer fits its type' case propagation clears")
    }

    // MARK: - Entity clamps (§8 fixed caps)

    func testCreateAssetClampsName() throws {
        let cat = try store.createCategory(name: "Cat")
        let longName = String(repeating: "n", count: TextLimits.assetName + 50)
        let asset = try store.createAsset(name: longName, categoryID: cat.id)
        XCTAssertEqual(asset.name.count, TextLimits.assetName)
    }

    func testUpdateAssetClampsName() throws {
        let cat = try store.createCategory(name: "Cat")
        let asset = try store.createAsset(name: "Short", categoryID: cat.id)
        try store.updateAsset(id: asset.id, name: String(repeating: "n", count: TextLimits.assetName + 50))
        XCTAssertEqual(asset.name.count, TextLimits.assetName)
    }

    func testCreateCategoryClampsName() throws {
        let cat = try store.createCategory(name: String(repeating: "c", count: TextLimits.categoryName + 50))
        XCTAssertEqual(cat.name.count, TextLimits.categoryName)
    }

    func testUpdateCategoryClampsName() throws {
        let cat = try store.createCategory(name: "Short")
        try store.updateCategory(id: cat.id, name: String(repeating: "c", count: TextLimits.categoryName + 50))
        XCTAssertEqual(cat.name.count, TextLimits.categoryName)
    }

    func testAddUserOptionClampsOption() throws {
        let list = store.createComboList(name: "List", isUserExtensible: true)
        try store.addUserOption(String(repeating: "o", count: TextLimits.comboListOption + 50), toComboListID: list.id)
        XCTAssertEqual(list.userOptions.first?.count, TextLimits.comboListOption)
    }

    func testAddEventClampsTitleAndNotes() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let event = try store.addEvent(
            title: String(repeating: "t", count: TextLimits.eventTitle + 50),
            date: Date(),
            notes: String(repeating: "n", count: TextLimits.eventNotes + 50),
            toAssetID: asset.id
        )
        XCTAssertEqual(event.title.count, TextLimits.eventTitle)
        XCTAssertEqual(event.notes.count, TextLimits.eventNotes)
    }

    func testUpdateEventClampsTitleAndNotes() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let event = try store.addEvent(title: "Short", date: Date(), toAssetID: asset.id)
        try store.updateEvent(
            id: event.id, onAssetID: asset.id,
            title: String(repeating: "t", count: TextLimits.eventTitle + 50), date: Date(),
            notes: String(repeating: "n", count: TextLimits.eventNotes + 50),
            recurrence: nil, due: DueSettings()
        )
        XCTAssertEqual(event.title.count, TextLimits.eventTitle)
        XCTAssertEqual(event.notes.count, TextLimits.eventNotes)
    }

    func testAddTransactionClampsDetailsAndNotes() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let txn = try store.addTransaction(
            details: String(repeating: "d", count: TextLimits.transactionDetails + 50),
            amount: 10, date: Date(), kind: .expense,
            notes: String(repeating: "n", count: TextLimits.transactionNotes + 50),
            toAssetID: asset.id
        )
        XCTAssertEqual(txn.details.count, TextLimits.transactionDetails)
        XCTAssertEqual(txn.notes.count, TextLimits.transactionNotes)
    }

    func testUpdatePhotoCaptionClamps() throws {
        let asset = try store.createAsset(name: "Asset", categoryID: try store.createCategory(name: "Cat").id)
        let photo = try store.addPhoto(imageData: Data(), thumbnailData: Data(), toAssetID: asset.id)
        try store.updatePhotoCaption(String(repeating: "c", count: TextLimits.photoCaption + 50), forPhotoID: photo.id, onAssetID: asset.id)
        XCTAssertEqual(photo.caption.count, TextLimits.photoCaption)
    }
}
