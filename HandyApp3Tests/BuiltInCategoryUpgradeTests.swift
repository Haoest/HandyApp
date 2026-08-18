import XCTest
@testable import HandyApp3

final class BuiltInCategoryUpgradeTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    private var applianceID: UUID { BuiltInTypes.deterministicID("category.\(SystemCategory.appliance.rawValue)") }
    private var oldRetailerFieldID: UUID { BuiltInTypes.deterministicID("field.appliance.Retailer") }
    private var newRetailerFieldID: UUID { BuiltInTypes.deterministicID("field.appliance.Retailer.comboList") }

    private func makeOldTextRetailer() -> AssetProperty {
        AssetProperty(
            id: oldRetailerFieldID,
            definition: PropertyDefinition(id: oldRetailerFieldID, name: "Retailer", type: .basic(.text), isRequired: false)
        )
    }

    // an install that seeded Appliance back when Retailer was free text gets that field retired
    // and replaced by the combo-list field under its own new id, plus any other canonical
    // fields it never had
    func testUpgradeRetiresOldRetailerFieldAndAddsComboListReplacement() throws {
        let cat = try store.createCategory(id: applianceID, name: SystemCategory.appliance.rawValue, propertyTemplates: [makeOldTextRetailer()])

        let changed = store.upgradeBuiltInCategories()

        XCTAssertEqual(changed, BuiltInTypes.categoryTemplates[.appliance]!.count + 1)

        let oldField = try XCTUnwrap(cat.propertyTemplates.first { $0.id == oldRetailerFieldID })
        XCTAssertTrue(oldField.isDeleted)
        XCTAssertEqual(oldField.definition.type, .basic(.text), "retirement tombstones the old field, it doesn't mutate its type")

        let newField = try XCTUnwrap(cat.propertyTemplates.first { $0.id == newRetailerFieldID })
        XCTAssertFalse(newField.isDeleted)
        guard case .comboList(let list) = newField.definition.type else {
            return XCTFail("Retailer should have been replaced by a combo list field")
        }
        XCTAssertEqual(list.name, "Retailer")
        XCTAssertEqual(list.allOptions, ["Home Depot", "Lowes"])
        XCTAssertTrue(list.systemOptions.isEmpty, "Home Depot / Lowes must be writable user options, not locked system options")

        XCTAssertNotNil(cat.propertyTemplates.first { $0.definition.name == "Notes" })
    }

    // a field the user already tombstoned themselves is not retired again, and the retirement
    // pass is idempotent — running the upgrade twice doesn't touch it further
    func testUpgradeLeavesAlreadyTombstonedOldFieldAlone() throws {
        let cat = try store.createCategory(id: applianceID, name: SystemCategory.appliance.rawValue, propertyTemplates: [makeOldTextRetailer()])
        try store.removeTemplateProperty(id: oldRetailerFieldID, fromCategoryID: cat.id)

        store.upgradeBuiltInCategories()

        let oldCopies = cat.propertyTemplates.filter { $0.id == oldRetailerFieldID }
        XCTAssertEqual(oldCopies.count, 1)
        XCTAssertTrue(oldCopies[0].isDeleted)
        // the replacement combo-list field is unaffected by the old field's tombstone history
        XCTAssertNotNil(cat.propertyTemplates.first { $0.id == newRetailerFieldID && !$0.isDeleted })
    }

    // a category the user deleted is skipped entirely, not silently repopulated with fields
    func testUpgradeSkipsDeletedCategory() throws {
        let cat = try store.createCategory(id: applianceID, name: SystemCategory.appliance.rawValue, propertyTemplates: [])
        try store.softDeleteCategory(id: cat.id)

        let changed = store.upgradeBuiltInCategories()

        XCTAssertEqual(changed, 0)
        XCTAssertTrue(cat.propertyTemplates.isEmpty)
    }

    // a category that was never seeded on this install has nothing to upgrade
    func testUpgradeIsNoOpWhenCategoryNotYetSeeded() {
        XCTAssertEqual(store.upgradeBuiltInCategories(), 0)
    }
}
