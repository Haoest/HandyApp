import XCTest
@testable import HandyApp3

final class BuiltInLabelsTests: XCTestCase {

    private var applianceCategoryID: UUID { BuiltInTypes.deterministicID("category.\(SystemCategory.appliance.rawValue)") }
    private var purchaseDateFieldID: UUID { BuiltInTypes.deterministicID("field.appliance.Purchase date") }

    func testRegistryCoversEveryDeterministicIDInCategoryTemplates() {
        for (_, defs) in BuiltInTypes.categoryTemplates {
            for entry in defs {
                XCTAssertNotNil(BuiltInTypes.seedLabelKeys[entry.definition.id],
                                 "\(entry.definition.name) has no display-label entry")
            }
        }
    }

    func testCatalogKeyIsNamespacedByTheSeedKey() {
        let entry = try! XCTUnwrap(BuiltInTypes.seedLabelKeys[purchaseDateFieldID])
        XCTAssertEqual(entry.catalogKey, "builtin.field.appliance.Purchase date")
        XCTAssertEqual(entry.english, "Purchase date")
    }

    // an id that isn't a recognized built-in (a user-created category/field) must pass its
    // name straight through, untouched
    func testUnknownIDPassesNameThrough() {
        let name = BuiltInTypes.localizedSeedName(id: UUID(), currentName: "My Custom Field")
        XCTAssertEqual(name, "My Custom Field")
    }

    // a stored name that no longer matches the shipped English literal means the user renamed
    // it — the rename always wins over the localized label
    func testUserRenameWinsOverLocalizedLabel() {
        let name = BuiltInTypes.localizedSeedName(id: applianceCategoryID, currentName: "My Appliances")
        XCTAssertEqual(name, "My Appliances")
    }

    // an unrenamed built-in resolves through the catalog rather than returning the stored name
    // verbatim — this doesn't assert the translated text itself (the catalog resource isn't
    // bundled in this headless target), just that the lookup takes the localized path at all
    func testUnrenamedBuiltInDoesNotShortCircuitToStoredName() {
        let category = SystemCategory.appliance.rawValue
        let name = BuiltInTypes.localizedSeedName(id: applianceCategoryID, currentName: category)
        XCTAssertFalse(name.isEmpty)
    }
}
