import XCTest
@testable import HandyApp3

final class TemplatePropagationTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    // a field added to the category after the asset existed is appended, carrying the
    // template's default value
    func testAddedTemplateFieldAppearsOnExistingAsset() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        XCTAssertEqual(asset.baseProperties.count, 1)

        let retailerDef = PropertyDefinition(name: "Retailer", type: .basic(.text), isRequired: false)
        try store.appendTemplateProperty(definition: retailerDef, value: .text("Home Depot"), toCategoryID: cat.id)

        let summary = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.affectedAssetCount, 1)

        let added = try XCTUnwrap(asset.baseProperties.first { $0.definition.id == retailerDef.id })
        XCTAssertEqual(added.value, .text("Home Depot"))
        XCTAssertEqual(added.sortOrder, asset.baseProperties[0].sortOrder + AssetProperty.sortOrderIncrement)
    }

    // a value the user already typed into an existing field survives propagation untouched
    func testExistingValuesArePreserved() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.setPropertyValue(.text("Bosch"), forDefinitionID: cat.propertyTemplates[0].definition.id, onAssetID: asset.id)

        try store.addTemplateProperty(
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false)),
            toCategoryID: cat.id
        )
        try store.propagateTemplates(forCategoryID: cat.id)

        XCTAssertEqual(asset.baseProperties[0].value, .text("Bosch"))
    }

    // removing a template field tombstones the matching base property rather than dropping it —
    // sync-safety requires a tombstone, not a hard remove
    func testRemovedTemplateFieldIsTombstonedNotDropped() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text))),
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false))
        ])
        let notesDefID = cat.propertyTemplates[1].definition.id
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.removeTemplateProperty(id: cat.propertyTemplates[1].id, fromCategoryID: cat.id)

        let summary = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(summary.removed, 1)

        XCTAssertEqual(asset.baseProperties.count, 2, "tombstoned, not removed from the array")
        let removed = try XCTUnwrap(asset.baseProperties.first { $0.definition.id == notesDefID })
        XCTAssertTrue(removed.isDeleted)
        XCTAssertNotNil(removed.deletedAt)
        XCTAssertFalse(asset.liveBaseProperties.contains { $0.definition.id == notesDefID })
        XCTAssertNil(asset.value(for: notesDefID))
        XCTAssertThrowsError(try store.setPropertyValue(.text("x"), forDefinitionID: notesDefID, onAssetID: asset.id))
    }

    // a rename refreshes the asset's copy of the definition and keeps the value
    func testRenameRefreshesDefinitionAndKeepsValue() throws {
        let makeDef = PropertyDefinition(name: "Make", type: .basic(.text))
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [AssetProperty(definition: makeDef)])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.setPropertyValue(.text("Bosch"), forDefinitionID: makeDef.id, onAssetID: asset.id)

        try store.updateTemplateProperty(id: cat.propertyTemplates[0].id, inCategoryID: cat.id, name: "Manufacturer")

        let summary = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(summary.refreshed, 1)
        XCTAssertEqual(summary.valuesCleared, 0)

        let prop = asset.baseProperties[0]
        XCTAssertEqual(prop.definition.name, "Manufacturer")
        XCTAssertEqual(prop.value, .text("Bosch"))
    }

    // a type change keeps a value that still validates against the new type — mirroring the
    // real Appliance "Retailer" text-to-combo-list migration, where a preserved value must also
    // be registered on the (extensible) combo list it's now backed by
    func testTypeChangeKeepsStillValidValue() throws {
        let retailerList = store.createComboList(name: "Retailer", userOptions: ["Home Depot", "Lowes"])
        let retailerDef = PropertyDefinition(name: "Retailer", type: .basic(.text), isRequired: false)
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [AssetProperty(definition: retailerDef)])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.setPropertyValue(.text("Costco"), forDefinitionID: retailerDef.id, onAssetID: asset.id)

        try store.updateTemplateProperty(id: cat.propertyTemplates[0].id, inCategoryID: cat.id, type: .comboList(retailerList))
        let summary = try store.propagateTemplates(forCategoryID: cat.id)

        XCTAssertEqual(summary.valuesCleared, 0)
        XCTAssertEqual(asset.baseProperties[0].value, .text("Costco"))
        XCTAssertTrue(retailerList.userOptions.contains("Costco"), "preserved value registers on the extensible list")
    }

    // a type change clears a value that no longer validates against the new type
    func testTypeChangeClearsInvalidValue() throws {
        let warrantyDef = PropertyDefinition(name: "Warranty", type: .basic(.text), isRequired: false)
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [AssetProperty(definition: warrantyDef)])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.setPropertyValue(.text("2 years"), forDefinitionID: warrantyDef.id, onAssetID: asset.id)

        try store.updateTemplateProperty(id: cat.propertyTemplates[0].id, inCategoryID: cat.id, type: .basic(.number))
        let summary = try store.propagateTemplates(forCategoryID: cat.id)

        XCTAssertEqual(summary.refreshed, 1)
        XCTAssertEqual(summary.valuesCleared, 1)
        XCTAssertNil(asset.baseProperties[0].value)
    }

    // a soft-deleted asset is skipped entirely — touching it would rescue it from the
    // retention sweep
    func testSoftDeletedAssetIsSkipped() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        let originalCount = asset.baseProperties.count
        try store.softDeleteAsset(id: asset.id)
        // Captured after the soft delete, which itself stamps modifiedDate — the assertion
        // below is about propagateTemplates leaving it alone from here, not about the delete.
        let originalModifiedDate = asset.modifiedDate

        try store.addTemplateProperty(
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false)),
            toCategoryID: cat.id
        )
        let summary = try store.propagateTemplates(forCategoryID: cat.id)

        XCTAssertEqual(summary.eligibleAssetCount, 0)
        XCTAssertEqual(asset.baseProperties.count, originalCount)
        XCTAssertEqual(asset.modifiedDate, originalModifiedDate)
        XCTAssertFalse(asset.isProtectedFromAutoPurge)
    }

    // a purged asset is skipped without throwing
    func testPurgedAssetIsSkipped() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.softDeleteAsset(id: asset.id)
        try store.hardDeleteAsset(id: asset.id)

        try store.addTemplateProperty(
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false)),
            toCategoryID: cat.id
        )
        let summary = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(summary.eligibleAssetCount, 0)
        XCTAssertTrue(asset.baseProperties.isEmpty)
    }

    // a new template field is not appended as a base property when a live custom property
    // already claims the same definition id — that would shadow the custom property, since
    // base properties are searched before custom ones
    func testCustomPropertyWithSameDefinitionIDIsNotShadowed() throws {
        let cat = try store.createCategory(name: "Appliance")
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        let sharedDef = PropertyDefinition(name: "Color", type: .basic(.text), isRequired: false)
        try store.addCustomProperty(definition: sharedDef, value: .text("Black"), toAssetID: asset.id)

        try store.addTemplateProperty(AssetProperty(definition: sharedDef), toCategoryID: cat.id)
        let summary = try store.propagateTemplates(forCategoryID: cat.id)

        XCTAssertEqual(summary.added, 0)
        XCTAssertFalse(asset.baseProperties.contains { $0.definition.id == sharedDef.id })
        XCTAssertEqual(asset.value(for: sharedDef.id), .text("Black"))
    }

    // a second run with nothing new to reconcile is a true no-op
    func testPropagationIsIdempotent() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.addTemplateProperty(
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false)),
            toCategoryID: cat.id
        )
        try store.propagateTemplates(forCategoryID: cat.id)
        let modifyDatesAfterFirstRun = asset.baseProperties.map(\.modifyDate)

        let second = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(asset.baseProperties.map(\.modifyDate), modifyDatesAfterFirstRun, "an unchanged property must not be touched again")
    }

    // the dry run and the apply must always agree — the confirmation dialog can never promise
    // something the apply doesn't do
    func testPreviewMatchesApply() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        _ = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.addTemplateProperty(
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false)),
            toCategoryID: cat.id
        )

        let preview = try store.previewTemplatePropagation(forCategoryID: cat.id)
        let applied = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(preview, applied)
    }

    // headModifyDate must never move — bumping it would let this bulk op outrank a concurrent
    // delete or rename of the same asset on a peer device
    func testHeadModifyDateIsNotBumped() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        let originalHeadModifyDate = asset.headModifyDate
        try store.addTemplateProperty(
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false)),
            toCategoryID: cat.id
        )

        try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(asset.headModifyDate, originalHeadModifyDate)
        XCTAssertGreaterThan(asset.modifiedDate, originalHeadModifyDate)
    }

    // a base property tombstoned by an earlier propagation is revived, not duplicated, if the
    // template comes back live
    func testTombstonedBasePropertyIsRevivedNotDuplicated() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text))),
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false))
        ])
        let notesTemplateID = cat.propertyTemplates[1].id
        let notesDefID = cat.propertyTemplates[1].definition.id
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.setPropertyValue(.text("keep me"), forDefinitionID: notesDefID, onAssetID: asset.id)

        try store.removeTemplateProperty(id: notesTemplateID, fromCategoryID: cat.id)
        try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertTrue(asset.baseProperties.first { $0.definition.id == notesDefID }!.isDeleted)

        // simulate the template coming back live, e.g. a peer's re-add synced in
        cat.propertyTemplates[1].isDeleted = false
        cat.propertyTemplates[1].deletedAt = nil

        let summary = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(summary.added, 1)
        let matches = asset.baseProperties.filter { $0.definition.id == notesDefID }
        XCTAssertEqual(matches.count, 1, "must revive the existing record, not append a second one")
        XCTAssertFalse(matches[0].isDeleted)
        XCTAssertEqual(matches[0].value, .text("keep me"), "the old value survives a revive")
    }

    // purgeHardDeleted reaps an aged-out base-property tombstone, same as it already does for
    // custom properties, photos, events, and transactions
    func testExpiredBasePropertyTombstoneIsReaped() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text))),
            AssetProperty(definition: PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.removeTemplateProperty(id: cat.propertyTemplates[1].id, fromCategoryID: cat.id)
        try store.propagateTemplates(forCategoryID: cat.id)

        let tombstoned = try XCTUnwrap(asset.baseProperties.first { $0.isDeleted })
        tombstoned.deletedAt = Date().addingTimeInterval(-200 * 86_400)

        store.purgeHardDeleted(olderThan: 90 * 86_400)
        XCTAssertEqual(asset.baseProperties.count, 1)
    }

    // MARK: - Reorder propagation

    // when a category's fields are reordered, "Update Existing Assets" must carry the new
    // order onto assets created before the reorder — the base-field order is otherwise frozen
    // at asset-creation time
    func testReorderedTemplateCarriesNewSortOrderToExistingAsset() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "Model", type: .basic(.text)), sortOrder: 10),
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        XCTAssertEqual(asset.baseProperties.sorted(by: SortOrdering.precedes).map(\.definition.name), ["Make", "Model"])

        // The drag leaves Model at -10 (a midpoint/edge value, not a ladder rung).
        try store.moveTemplateProperties(fromOffsets: [1], toOffset: 0, inCategoryID: cat.id)

        let summary = try store.propagateTemplates(forCategoryID: cat.id)
        // Both properties move: the run normalizes to the 0/10 ladder first, so Model goes
        // -10 → 0 and Make 0 → 10.
        XCTAssertEqual(summary.reordered, 2)
        XCTAssertEqual(summary.affectedAssetCount, 1)
        XCTAssertFalse(summary.isEmpty, "an order-only difference must still be actionable")

        XCTAssertEqual(asset.baseProperties.sorted(by: SortOrdering.precedes).map(\.definition.name), ["Model", "Make"])
    }

    // the run flattens the category's own templates onto a clean ladder in display order,
    // rather than propagating whatever fractional values a drag happened to leave behind
    func testPropagationNormalizesTemplateSortOrders() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "Model", type: .basic(.text)), sortOrder: 10),
            AssetProperty(definition: PropertyDefinition(name: "Year", type: .basic(.text)), sortOrder: 20),
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        // Drop "Year" between Make and Model — a midpoint write, leaving sortOrder 5.
        try store.moveTemplateProperties(fromOffsets: [2], toOffset: 1, inCategoryID: cat.id)
        XCTAssertEqual(cat.liveTemplates.first { $0.definition.name == "Year" }?.sortOrder, 5)

        try store.propagateTemplates(forCategoryID: cat.id)

        let templates = cat.liveTemplates.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(templates.map(\.definition.name), ["Make", "Year", "Model"])
        XCTAssertEqual(templates.map(\.sortOrder), [0, 10, 20], "templates must be flattened onto the ladder")

        let props = asset.baseProperties.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(props.map(\.definition.name), ["Make", "Year", "Model"])
        XCTAssertEqual(props.map(\.sortOrder), [0, 10, 20], "assets receive the normalized ladder, not the 5")
    }

    // normalization is the point of the action, so it runs even for a category whose assets
    // need no other change — and stays idempotent afterwards
    func testPropagationNormalizesTemplatesEvenWithNoAssets() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "Model", type: .basic(.text)), sortOrder: 10),
        ])
        try store.moveTemplateProperties(fromOffsets: [1], toOffset: 0, inCategoryID: cat.id)
        XCTAssertEqual(cat.liveTemplates.first { $0.definition.name == "Model" }?.sortOrder, -10)

        try store.propagateTemplates(forCategoryID: cat.id)

        let templates = cat.liveTemplates.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(templates.map(\.definition.name), ["Model", "Make"])
        XCTAssertEqual(templates.map(\.sortOrder), [0, 10])

        let second = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(cat.liveTemplates.sorted(by: SortOrdering.precedes).map(\.sortOrder), [0, 10])
    }

    func testPropagationIsANoOpWhenOrderAlreadyMatches() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "Model", type: .basic(.text)), sortOrder: 10),
        ])
        _ = try store.createAsset(name: "Fridge", categoryID: cat.id)

        let summary = try store.propagateTemplates(forCategoryID: cat.id)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.reordered, 0)
    }
}
