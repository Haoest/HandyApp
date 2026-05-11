import XCTest
@testable import HandyApp3

final class HandyApp3Tests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    // MARK: - AssetCategory CRUD

    func testCreateCategory() {
        let cat = store.createCategory(name: "Appliance")
        XCTAssertEqual(store.allCategories.count, 1)
        XCTAssertEqual(cat.name, "Appliance")
        XCTAssertTrue(cat.propertyTemplates.isEmpty)
    }

    func testUpdateCategoryName() throws {
        let cat = store.createCategory(name: "Old")
        try store.updateCategory(id: cat.id, name: "New")
        XCTAssertEqual(cat.name, "New")
    }

    func testDeleteCategory() throws {
        let cat = store.createCategory(name: "Temp")
        try store.deleteCategory(id: cat.id)
        XCTAssertTrue(store.allCategories.isEmpty)
    }

    func testDeleteCategoryUnknown() {
        XCTAssertThrowsError(try store.deleteCategory(id: UUID())) { error in
            if case AssetStoreError.categoryNotFound = error { } else { XCTFail("wrong error") }
        }
    }

    func testAddTemplateProperty() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Make", type: .basic(.text))
        let template = AssetProperty(definition: def)
        try store.addTemplateProperty(template, toCategoryID: cat.id)
        XCTAssertEqual(cat.propertyTemplates.count, 1)
        XCTAssertEqual(cat.propertyTemplates[0].definition.name, "Make")
    }

    func testRemoveTemplateProperty() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Make", type: .basic(.text))
        let template = AssetProperty(definition: def)
        try store.addTemplateProperty(template, toCategoryID: cat.id)
        try store.removeTemplateProperty(id: template.id, fromCategoryID: cat.id)
        XCTAssertTrue(cat.propertyTemplates.isEmpty)
    }

    // MARK: - Asset creation from category

    func testCreateAssetCopiesTemplates() throws {
        let cat = store.createCategory(name: "Car")
        let makeDef = PropertyDefinition(name: "Make", type: .basic(.text))
        let yearDef = PropertyDefinition(name: "Year", type: .basic(.number))
        try store.addTemplateProperty(AssetProperty(definition: makeDef), toCategoryID: cat.id)
        try store.addTemplateProperty(AssetProperty(definition: yearDef), toCategoryID: cat.id)

        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)

        XCTAssertEqual(asset.baseProperties.count, 2)
        XCTAssertEqual(asset.baseProperties[0].definition.name, "Make")
        XCTAssertEqual(asset.baseProperties[1].definition.name, "Year")
        XCTAssertNil(asset.baseProperties[0].value)
    }

    func testCreateAssetBasePropertiesAreIndependent() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Make", type: .basic(.text))
        try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)

        let car1 = try store.createAsset(name: "Car 1", categoryID: cat.id)
        let car2 = try store.createAsset(name: "Car 2", categoryID: cat.id)

        try store.setPropertyValue(.text("Toyota"), forDefinitionID: car1.baseProperties[0].definition.id, onAssetID: car1.id)
        XCTAssertNil(car2.baseProperties[0].value)
    }

    func testCreateAssetUnknownCategory() {
        XCTAssertThrowsError(try store.createAsset(name: "X", categoryID: UUID())) { error in
            if case AssetStoreError.categoryNotFound = error { } else { XCTFail("wrong error") }
        }
    }

    func testCreateAssetWithTemplateDefaultValue() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Fuel", type: .basic(.text))
        let template = AssetProperty(definition: def, value: .text("Gasoline"))
        try store.addTemplateProperty(template, toCategoryID: cat.id)

        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        XCTAssertEqual(asset.baseProperties[0].value, .text("Gasoline"))
    }

    // MARK: - Property value management

    func testSetBasePropertyValue() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Make", type: .basic(.text))
        try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)

        try store.setPropertyValue(.text("Toyota"), forDefinitionID: asset.baseProperties[0].definition.id, onAssetID: asset.id)
        XCTAssertEqual(asset.baseProperties[0].value, .text("Toyota"))
    }

    func testSetPropertyValueTypeMismatch() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Year", type: .basic(.number))
        try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)

        XCTAssertThrowsError(
            try store.setPropertyValue(.text("wrong"), forDefinitionID: asset.baseProperties[0].definition.id, onAssetID: asset.id)
        ) { error in
            if case AssetStoreError.typeMismatch = error { } else { XCTFail("wrong error") }
        }
    }

    func testRemovePropertyValue() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Make", type: .basic(.text))
        try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        let defID = asset.baseProperties[0].definition.id

        try store.setPropertyValue(.text("Toyota"), forDefinitionID: defID, onAssetID: asset.id)
        try store.removePropertyValue(forDefinitionID: defID, fromAssetID: asset.id)
        XCTAssertNil(asset.baseProperties[0].value)
    }

    func testSetPropertyValueUnknownDefinition() throws {
        let cat = store.createCategory(name: "Empty")
        let asset = try store.createAsset(name: "X", categoryID: cat.id)
        XCTAssertThrowsError(
            try store.setPropertyValue(.text("v"), forDefinitionID: UUID(), onAssetID: asset.id)
        ) { error in
            if case AssetStoreError.definitionNotFound = error { } else { XCTFail("wrong error") }
        }
    }

    // MARK: - Custom properties

    func testAddCustomProperty() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        let def = PropertyDefinition(name: "Notes", type: .basic(.text))

        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)
        XCTAssertEqual(asset.customProperties.count, 1)
        XCTAssertEqual(prop.definition.name, "Notes")
        XCTAssertNil(prop.value)
    }

    func testAddCustomPropertyWithInitialValue() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        let def = PropertyDefinition(name: "Notes", type: .basic(.text))

        let prop = try store.addCustomProperty(definition: def, value: .text("hello"), toAssetID: asset.id)
        XCTAssertEqual(prop.value, .text("hello"))
    }

    func testSetCustomPropertyValue() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        let def = PropertyDefinition(name: "Notes", type: .basic(.text))
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        try store.setCustomPropertyValue(.text("updated"), forCustomPropertyID: prop.id, onAssetID: asset.id)
        XCTAssertEqual(prop.value, .text("updated"))
    }

    func testRemoveCustomProperty() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        let def = PropertyDefinition(name: "Notes", type: .basic(.text))
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        try store.removeCustomProperty(id: prop.id, fromAssetID: asset.id)
        XCTAssertTrue(asset.customProperties.isEmpty)
    }

    func testUpdateCustomPropertyClearsValueOnTypeChange() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        let def = PropertyDefinition(name: "Mileage", type: .basic(.number))
        let prop = try store.addCustomProperty(definition: def, value: .number(50000), toAssetID: asset.id)

        try store.updateCustomProperty(id: prop.id, onAssetID: asset.id, type: .basic(.text))
        XCTAssertNil(prop.value)
        XCTAssertEqual(prop.definition.type, .basic(.text))
    }

    // MARK: - Asset value helper

    func testAssetValueHelperChecksBaseAndCustom() throws {
        let cat = store.createCategory(name: "Car")
        let baseDef = PropertyDefinition(name: "Make", type: .basic(.text))
        try store.addTemplateProperty(AssetProperty(definition: baseDef), toCategoryID: cat.id)
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        let baseDefID = asset.baseProperties[0].definition.id

        let customDef = PropertyDefinition(name: "Notes", type: .basic(.text))
        let customProp = try store.addCustomProperty(definition: customDef, toAssetID: asset.id)

        try store.setPropertyValue(.text("Toyota"), forDefinitionID: baseDefID, onAssetID: asset.id)
        try store.setCustomPropertyValue(.text("nice car"), forCustomPropertyID: customProp.id, onAssetID: asset.id)

        XCTAssertEqual(asset.value(for: baseDefID), .text("Toyota"))
        XCTAssertEqual(asset.value(for: customProp.definition.id), .text("nice car"))
        XCTAssertNil(asset.value(for: UUID()))
    }

    // MARK: - Asset lifecycle

    func testDeleteAsset() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "My Car", categoryID: cat.id)
        try store.deleteAsset(id: asset.id)
        XCTAssertNil(store.assets[asset.id])
    }

    func testDeleteAssetUnknown() {
        XCTAssertThrowsError(try store.deleteAsset(id: UUID())) { error in
            if case AssetStoreError.assetNotFound = error { } else { XCTFail("wrong error") }
        }
    }

    func testAssetsByCategoryID() throws {
        let car = store.createCategory(name: "Car")
        let appliance = store.createCategory(name: "Appliance")
        let a1 = try store.createAsset(name: "Camry", categoryID: car.id)
        let a2 = try store.createAsset(name: "Corolla", categoryID: car.id)
        _ = try store.createAsset(name: "Fridge", categoryID: appliance.id)

        let cars = try store.assets(ofCategoryID: car.id)
        XCTAssertEqual(Set(cars.map(\.id)), [a1.id, a2.id])
    }

    // MARK: - Asset containment hierarchy

    func testAddChild() throws {
        let cat = store.createCategory(name: "Generic")
        let house = try store.createAsset(name: "House", categoryID: cat.id)
        let fridge = try store.createAsset(name: "Fridge", categoryID: cat.id)

        try store.addChild(assetID: fridge.id, toParentID: house.id)

        XCTAssertEqual(house.children.count, 1)
        XCTAssertEqual(fridge.parent?.id, house.id)
    }

    func testHierarchyCycleSelf() throws {
        let cat = store.createCategory(name: "Generic")
        let asset = try store.createAsset(name: "X", categoryID: cat.id)

        XCTAssertThrowsError(try store.addChild(assetID: asset.id, toParentID: asset.id)) { error in
            if case AssetStoreError.hierarchyCycle = error { } else { XCTFail("wrong error") }
        }
    }

    func testHierarchyCycleAncestor() throws {
        let cat = store.createCategory(name: "Generic")
        let a = try store.createAsset(name: "A", categoryID: cat.id)
        let b = try store.createAsset(name: "B", categoryID: cat.id)
        let c = try store.createAsset(name: "C", categoryID: cat.id)

        try store.addChild(assetID: b.id, toParentID: a.id)
        try store.addChild(assetID: c.id, toParentID: b.id)

        XCTAssertThrowsError(try store.addChild(assetID: a.id, toParentID: c.id)) { error in
            if case AssetStoreError.hierarchyCycle = error { } else { XCTFail("wrong error") }
        }
    }

    func testRemoveFromParent() throws {
        let cat = store.createCategory(name: "Generic")
        let house = try store.createAsset(name: "House", categoryID: cat.id)
        let fridge = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.addChild(assetID: fridge.id, toParentID: house.id)

        try store.removeFromParent(assetID: fridge.id)
        XCTAssertTrue(house.children.isEmpty)
        XCTAssertNil(fridge.parent)
    }

    func testMoveAsset() throws {
        let cat = store.createCategory(name: "Generic")
        let house = try store.createAsset(name: "House", categoryID: cat.id)
        let garage = try store.createAsset(name: "Garage", categoryID: cat.id)
        let car = try store.createAsset(name: "Car", categoryID: cat.id)
        try store.addChild(assetID: car.id, toParentID: house.id)

        try store.moveAsset(assetID: car.id, toParentID: garage.id)
        XCTAssertTrue(house.children.isEmpty)
        XCTAssertEqual(garage.children.count, 1)
        XCTAssertEqual(car.parent?.id, garage.id)
    }

    func testDeleteAssetPromotesChildrenToGrandparent() throws {
        let cat = store.createCategory(name: "Generic")
        let house = try store.createAsset(name: "House", categoryID: cat.id)
        let room = try store.createAsset(name: "Room", categoryID: cat.id)
        let lamp = try store.createAsset(name: "Lamp", categoryID: cat.id)
        try store.addChild(assetID: room.id, toParentID: house.id)
        try store.addChild(assetID: lamp.id, toParentID: room.id)

        try store.deleteAsset(id: room.id)
        XCTAssertNil(store.assets[room.id])
        XCTAssertEqual(house.children.count, 1)
        XCTAssertEqual(house.children[0].id, lamp.id)
        XCTAssertEqual(lamp.parent?.id, house.id)
    }

    func testRootAssets() throws {
        let cat = store.createCategory(name: "Generic")
        let house = try store.createAsset(name: "House", categoryID: cat.id)
        let fridge = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.addChild(assetID: fridge.id, toParentID: house.id)

        let roots = store.rootAssets
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].id, house.id)
    }

    // MARK: - Composite value type (W × L)

    func testSeedBuiltInCompositeTypes() {
        store.seedBuiltInTypes()
        XCTAssertEqual(store.allCompositeTypes.count, 2)
        XCTAssertTrue(store.allCompositeTypes.contains(where: { $0.name == "W × L" }))
        XCTAssertTrue(store.allCompositeTypes.contains(where: { $0.name == "W × L × H" }))
    }

    func testSeedBuiltInTypesIdempotent() {
        store.seedBuiltInTypes()
        store.seedBuiltInTypes()
        XCTAssertEqual(store.allCompositeTypes.count, 2)
    }

    func testSetCompositePropertyValue() throws {
        store.seedBuiltInTypes()
        let wxl = store.allCompositeTypes.first(where: { $0.name == "W × L" })!

        let cat = store.createCategory(name: "Room")
        let def = PropertyDefinition(name: "Dimensions", type: .composite(wxl))
        try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Living Room", categoryID: cat.id)
        let defID = asset.baseProperties[0].definition.id

        try store.setPropertyValue(
            .composite(["Width": .number(12), "Length": .number(15)]),
            forDefinitionID: defID,
            onAssetID: asset.id
        )
        XCTAssertEqual(asset.baseProperties[0].value, .composite(["Width": .number(12), "Length": .number(15)]))
    }

    func testCompositeRequiredFieldMissing() throws {
        store.seedBuiltInTypes()
        let wxl = store.allCompositeTypes.first(where: { $0.name == "W × L" })!

        let cat = store.createCategory(name: "Room")
        let def = PropertyDefinition(name: "Dimensions", type: .composite(wxl))
        try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Living Room", categoryID: cat.id)

        XCTAssertThrowsError(
            try store.setPropertyValue(
                .composite(["Width": .number(12)]),
                forDefinitionID: asset.baseProperties[0].definition.id,
                onAssetID: asset.id
            )
        ) { error in
            if case AssetStoreError.compositeFieldMismatch = error { } else { XCTFail("wrong error") }
        }
    }

    // MARK: - ComboList

    func testSeedBuiltInComboLists() {
        store.seedBuiltInComboLists()
        XCTAssertTrue(store.allComboListDefinitions.contains(where: { $0.name == "Power Source" }))
    }

    func testSetComboListPropertyValue() throws {
        store.seedBuiltInComboLists()
        let powerSource = store.allComboListDefinitions.first(where: { $0.name == "Power Source" })!

        let cat = store.createCategory(name: "Appliance")
        let def = PropertyDefinition(name: "Power", type: .comboList(powerSource))
        try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Range", categoryID: cat.id)

        try store.setPropertyValue(.text("Gas"), forDefinitionID: asset.baseProperties[0].definition.id, onAssetID: asset.id)
        XCTAssertEqual(asset.baseProperties[0].value, .text("Gas"))
    }



    // MARK: - Real-world scenario

    func testHouseWithRoomAndAppliance() throws {
        let houseCat = store.createCategory(name: "House")
        let roomCat = store.createCategory(name: "Room")
        let applianceCat = store.createCategory(name: "Appliance")

        let house = try store.createAsset(name: "My House", categoryID: houseCat.id)
        let kitchen = try store.createAsset(name: "Kitchen", categoryID: roomCat.id)
        let fridge = try store.createAsset(name: "Fridge", categoryID: applianceCat.id)

        try store.addChild(assetID: kitchen.id, toParentID: house.id)
        try store.addChild(assetID: fridge.id, toParentID: kitchen.id)

        let serialDef = PropertyDefinition(name: "Serial Number", type: .basic(.text))
        let serialProp = try store.addCustomProperty(definition: serialDef, toAssetID: fridge.id)
        try store.setCustomPropertyValue(.text("SN-12345"), forCustomPropertyID: serialProp.id, onAssetID: fridge.id)

        XCTAssertEqual(house.descendants.count, 2)
        XCTAssertEqual(fridge.ancestors.map(\.name), ["My House", "Kitchen"])
        XCTAssertEqual(serialProp.value, .text("SN-12345"))
    }
}
