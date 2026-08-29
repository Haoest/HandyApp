import XCTest
@testable import HandyApp3

@MainActor
final class ComboListUsageTests: XCTestCase {

    private func makeStore() -> AssetStore {
        let store = AssetStore()
        store.seedBuiltInComboLists()
        return store
    }

    // MARK: - Off-list answers

    func testExtensibilityTogglesAndStampsModifyDate() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["Petrol"], isUserExtensible: true)
        let before = list.modifyDate

        try store.setComboListExtensible(id: list.id, false)
        XCTAssertFalse(list.isUserExtensible)
        XCTAssertGreaterThan(list.modifyDate, before)
    }

    func testSettingExtensibilityToItsCurrentValueDoesNotRestamp() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", isUserExtensible: true)
        let before = list.modifyDate
        try store.setComboListExtensible(id: list.id, true)
        XCTAssertEqual(list.modifyDate, before)
    }

    /// The whole point of the toggle: a closed list stops swallowing typed values.
    func testClosedListNoLongerAutoAddsTypedValues() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["Petrol"], isUserExtensible: true)

        store.handleComboListAutoAdd(stored: .text("Diesel"), type: .comboList(list))
        XCTAssertEqual(list.userOptions, ["Petrol", "Diesel"])

        try store.setComboListExtensible(id: list.id, false)
        store.handleComboListAutoAdd(stored: .text("Hydrogen"), type: .comboList(list))
        XCTAssertEqual(list.userOptions, ["Petrol", "Diesel"])
    }

    /// Narrowing the list must not blank values already stored against it.
    func testClosingAListLeavesStoredValuesAlone() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["Petrol"], isUserExtensible: true)
        let definition = PropertyDefinition(name: "Fuel", type: .comboList(list), isRequired: false)
        let category = try store.createCategory(name: "Car", propertyTemplates: [AssetProperty(definition: definition)])
        let asset = try store.createAsset(name: "Camry", categoryID: category.id)
        try store.setPropertyValue(.text("Petrol"), forDefinitionID: definition.id, onAssetID: asset.id)

        try store.setComboListExtensible(id: list.id, false)
        XCTAssertEqual(asset.value(for: definition.id), .text("Petrol"))
    }

    // MARK: - Reordering

    func testMovingAUserOptionUpAndDown() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["A", "B", "C"])

        try store.moveUserOption("C", inComboListID: list.id, by: -1)
        XCTAssertEqual(list.userOptions, ["A", "C", "B"])

        try store.moveUserOption("A", inComboListID: list.id, by: 1)
        XCTAssertEqual(list.userOptions, ["C", "A", "B"])
    }

    func testMovingPastEitherEndIsANoOp() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["A", "B"])
        let before = list.modifyDate

        try store.moveUserOption("A", inComboListID: list.id, by: -1)
        try store.moveUserOption("B", inComboListID: list.id, by: 1)
        XCTAssertEqual(list.userOptions, ["A", "B"])
        XCTAssertEqual(list.modifyDate, before)
    }

    func testMovingAnUnknownOptionIsANoOp() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["A", "B"])
        try store.moveUserOption("Z", inComboListID: list.id, by: 1)
        XCTAssertEqual(list.userOptions, ["A", "B"])
    }

    /// System options sit ahead of `userOptions` in `allOptions` and take no part in ordering.
    func testSystemOptionsAreNotReorderable() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", systemOptions: ["Petrol"], userOptions: ["Diesel"])
        try store.moveUserOption("Petrol", inComboListID: list.id, by: 1)
        XCTAssertEqual(list.allOptions, ["Petrol", "Diesel"])
    }

    // MARK: - Usage

    func testTemplateAndCustomFieldsAreBothFound() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["Petrol"])
        let templateDef = PropertyDefinition(name: "Fuel", type: .comboList(list), isRequired: false)
        let category = try store.createCategory(name: "Car", propertyTemplates: [AssetProperty(definition: templateDef)])
        let asset = try store.createAsset(name: "Camry", categoryID: category.id)
        try store.addCustomProperty(
            definition: PropertyDefinition(name: "Spare fuel", type: .comboList(list), isRequired: false),
            value: nil, toAssetID: asset.id
        )

        let references = ComboListUsage.references(toComboListID: list.id,
                                                  categories: store.allCategories,
                                                  assets: store.allAssets)
        XCTAssertEqual(references.count, 2)
        XCTAssertEqual(references.filter(\.isTemplate).first?.ownerName, "Car")
        XCTAssertEqual(references.filter { !$0.isTemplate }.first?.fieldName, "Spare fuel")
    }

    /// A base property is the asset's copy of a template already listed, so counting it too
    /// would report the same field twice.
    func testAnAssetsCopyOfATemplateIsNotASeparateReference() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["Petrol"])
        let templateDef = PropertyDefinition(name: "Fuel", type: .comboList(list), isRequired: false)
        let category = try store.createCategory(name: "Car", propertyTemplates: [AssetProperty(definition: templateDef)])
        _ = try store.createAsset(name: "Camry", categoryID: category.id)
        _ = try store.createAsset(name: "Civic", categoryID: category.id)

        let references = ComboListUsage.references(toComboListID: list.id,
                                                  categories: store.allCategories,
                                                  assets: store.allAssets)
        XCTAssertEqual(references.count, 1)
    }

    func testUnrelatedListsAreNotReported() throws {
        let store = makeStore()
        let used = store.createComboList(name: "Fuel")
        let unused = store.createComboList(name: "Colour")
        let definition = PropertyDefinition(name: "Fuel", type: .comboList(used), isRequired: false)
        _ = try store.createCategory(name: "Car", propertyTemplates: [AssetProperty(definition: definition)])

        XCTAssertTrue(ComboListUsage.references(toComboListID: unused.id,
                                                categories: store.allCategories,
                                                assets: store.allAssets).isEmpty)
    }

    /// Stored-value counts *do* include an asset's copy of a template field — here we want what
    /// would actually change if the option were renamed, not what is navigable.
    func testStoredValueCountSpansEveryThingHoldingTheOption() throws {
        let store = makeStore()
        let list = store.createComboList(name: "Fuel", userOptions: ["Petrol", "Diesel"])
        let definition = PropertyDefinition(name: "Fuel", type: .comboList(list), isRequired: false)
        let category = try store.createCategory(name: "Car", propertyTemplates: [AssetProperty(definition: definition)])
        let camry = try store.createAsset(name: "Camry", categoryID: category.id)
        let civic = try store.createAsset(name: "Civic", categoryID: category.id)
        try store.setPropertyValue(.text("Petrol"), forDefinitionID: definition.id, onAssetID: camry.id)
        try store.setPropertyValue(.text("Petrol"), forDefinitionID: definition.id, onAssetID: civic.id)

        XCTAssertEqual(ComboListUsage.storedValueCount(of: "Petrol", listID: list.id, assets: store.allAssets), 2)
        XCTAssertEqual(ComboListUsage.storedValueCount(of: "Diesel", listID: list.id, assets: store.allAssets), 0)
    }
}
