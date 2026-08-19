import XCTest
@testable import HandyApp3

/// Coverage for combo list soft-delete, purge exemption, seeding idempotency, and the
/// `handleComboListAutoAdd` write paths added alongside the `ComboListField` UI.
final class ComboListTests: XCTestCase {

    var store: AssetStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir
        store = AssetStore()
    }

    override func tearDown() {
        super.tearDown()
        AssetStore.baseDirOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Soft delete / restore

    func testSoftDeleteHidesFromLiveListButKeepsRawEntry() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood", "Metal"])
        try store.softDeleteComboList(id: list.id)

        XCTAssertFalse(store.allComboListDefinitions.contains(where: { $0.id == list.id }))
        XCTAssertTrue(store.deletedComboListDefinitions.contains(where: { $0.id == list.id }))
        XCTAssertNotNil(store.comboListDefinitions[list.id])
        XCTAssertTrue(list.isDeleted)
        XCTAssertNotNil(list.deletedAt)
    }

    func testRestoreClearsTombstone() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood"])
        try store.softDeleteComboList(id: list.id)
        try store.restoreComboList(id: list.id)

        XCTAssertFalse(list.isDeleted)
        XCTAssertNil(list.deletedAt)
        XCTAssertTrue(store.allComboListDefinitions.contains(where: { $0.id == list.id }))
    }

    /// The regression test for the silent-drop hazard: a property typed on a since-soft-deleted
    /// combo list must survive a save/load round trip intact, because `resolvePropertyType`
    /// looks the list up in the raw dict, not the live-only accessor.
    func testSoftDeletedComboListKeepsPropertyResolutionAcrossReload() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood", "Metal"])
        let cat = try store.createCategory(name: "Furniture")
        let def = PropertyDefinition(name: "Material", type: .comboList(list), isRequired: false)
        let asset = try store.createAsset(name: "Chair", categoryID: cat.id)
        try store.addCustomProperty(definition: def, value: .text("Wood"), toAssetID: asset.id)

        try store.softDeleteComboList(id: list.id)
        store.save()

        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())

        let reloadedAsset = try XCTUnwrap(reloaded.assets[asset.id])
        let prop = try XCTUnwrap(reloadedAsset.liveCustomProperties.first(where: { $0.definition.name == "Material" }))
        XCTAssertEqual(prop.value, .text("Wood"))
        let reloadedList = try XCTUnwrap(reloaded.comboListDefinitions[list.id])
        XCTAssertTrue(reloadedList.isDeleted)
    }

    // MARK: - Purge exemption

    func testPurgeHardDeletedLeavesComboListsIntact() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood", "Metal"])
        try store.softDeleteComboList(id: list.id)
        list.deletedAt = Date(timeIntervalSinceNow: -400 * 86_400)

        store.purgeHardDeleted(olderThan: 90 * 86_400)

        XCTAssertEqual(list.name, "Materials")
        XCTAssertEqual(list.allOptions, ["Wood", "Metal"])
        XCTAssertNotNil(store.comboListDefinitions[list.id])
    }

    // MARK: - Seeding idempotency

    func testSeedBuiltInComboListsIsIdempotentAfterRename() throws {
        store.seedBuiltInComboLists()
        XCTAssertEqual(store.comboListDefinitions.count, 2)
        let powerSource = try XCTUnwrap(store.allComboListDefinitions.first(where: { $0.name == "Power Source" }))
        try store.updateComboList(id: powerSource.id, name: "Energy")

        store.seedBuiltInComboLists()

        XCTAssertEqual(store.comboListDefinitions.count, 1)
        XCTAssertEqual(store.comboListDefinitions[powerSource.id]?.name, "Energy")
    }

    func testSeedBuiltInComboListsDoesNotResurrectDeleted() throws {
        store.seedBuiltInComboLists()
        let powerSource = try XCTUnwrap(store.allComboListDefinitions.first(where: { $0.name == "Power Source" }))
        try store.softDeleteComboList(id: powerSource.id)

        store.seedBuiltInComboLists()

        XCTAssertEqual(store.comboListDefinitions.count, 1)
        XCTAssertTrue(store.comboListDefinitions[powerSource.id]?.isDeleted ?? false)
    }

    /// Regression test for an install that ended up with "Power Source" under a
    /// non-deterministic id (e.g. from before the seeder's presence check was id-keyed) —
    /// the very first id-keyed seed must fold it into the canonical record rather than
    /// creating a second live list alongside it.
    func testSeedBuiltInComboListsMergesLegacyDuplicateUnderDifferentID() throws {
        let legacy = store.createComboList(name: "Power Source", userOptions: ["Diesel"])
        let deterministicID = BuiltInTypes.powerSourceComboList().id
        XCTAssertNotEqual(legacy.id, deterministicID)

        store.seedBuiltInComboLists()

        XCTAssertEqual(store.allComboListDefinitions.filter { $0.name == "Power Source" }.count, 1)
        let canonical = try XCTUnwrap(store.comboListDefinitions[deterministicID])
        XCTAssertFalse(canonical.isDeleted)
        XCTAssertTrue(canonical.allOptions.contains("Diesel"), "the legacy list's option must survive the merge")
        XCTAssertTrue(store.comboListDefinitions[legacy.id]?.isDeleted ?? false, "the legacy duplicate must be soft-deleted, not lost")
    }

    /// Same bug, but the canonical deterministic-id record already exists (as it would after
    /// this session's earlier id-keyed fix already seeded it once) with an orphaned legacy
    /// duplicate still lingering from before that.
    func testSeedBuiltInComboListsMergesStrayIntoAlreadyExistingCanonical() throws {
        store.seedBuiltInComboLists()
        let deterministicID = BuiltInTypes.powerSourceComboList().id
        let legacy = store.createComboList(name: "Power Source", userOptions: ["Diesel"])

        store.seedBuiltInComboLists()

        XCTAssertEqual(store.allComboListDefinitions.filter { $0.name == "Power Source" }.count, 1)
        let canonical = try XCTUnwrap(store.comboListDefinitions[deterministicID])
        XCTAssertTrue(canonical.allOptions.contains("Diesel"))
        XCTAssertTrue(store.comboListDefinitions[legacy.id]?.isDeleted ?? false)
    }

    // MARK: - Auto-add across every write path

    func testAutoAddFromSetTemplatePropertyValue() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood"])
        let cat = try store.createCategory(name: "Furniture")
        let def = PropertyDefinition(name: "Material", type: .comboList(list), isRequired: false)
        let prop = try store.addTemplateProperty(AssetProperty(definition: def), toCategoryID: cat.id)

        try store.setTemplatePropertyValue(.text("Bamboo"), forPropertyID: prop.id, inCategoryID: cat.id)

        XCTAssertTrue(list.userOptions.contains("Bamboo"))
    }

    func testAutoAddFromAddCustomProperty() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood"])
        let cat = try store.createCategory(name: "Furniture")
        let asset = try store.createAsset(name: "Chair", categoryID: cat.id)
        let def = PropertyDefinition(name: "Material", type: .comboList(list), isRequired: false)

        try store.addCustomProperty(definition: def, value: .text("Bamboo"), toAssetID: asset.id)

        XCTAssertTrue(list.userOptions.contains("Bamboo"))
    }

    func testAutoAddFromSetCustomPropertyValue() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood"])
        let cat = try store.createCategory(name: "Furniture")
        let asset = try store.createAsset(name: "Chair", categoryID: cat.id)
        let def = PropertyDefinition(name: "Material", type: .comboList(list), isRequired: false)
        let prop = try store.addCustomProperty(definition: def, toAssetID: asset.id)

        try store.setCustomPropertyValue(.text("Bamboo"), forCustomPropertyID: prop.id, onAssetID: asset.id)

        XCTAssertTrue(list.userOptions.contains("Bamboo"))
    }

    func testAutoAddFromAddTemplateProperty() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood"])
        let cat = try store.createCategory(name: "Furniture")
        let def = PropertyDefinition(name: "Material", type: .comboList(list), isRequired: false)

        try store.addTemplateProperty(AssetProperty(definition: def, value: .text("Bamboo")), toCategoryID: cat.id)

        XCTAssertTrue(list.userOptions.contains("Bamboo"))
    }

    func testAutoAddFromCreateCategory() throws {
        let list = store.createComboList(name: "Materials", userOptions: ["Wood"])
        let def = PropertyDefinition(name: "Material", type: .comboList(list), isRequired: false)

        _ = try store.createCategory(
            name: "Furniture",
            propertyTemplates: [AssetProperty(definition: def, value: .text("Bamboo"))]
        )

        XCTAssertTrue(list.userOptions.contains("Bamboo"))
    }

    // MARK: - Extensibility guards

    func testNonExtensibleComboListStillRejectsUnknownValueOnValidate() throws {
        let list = store.createComboList(name: "Fixed", systemOptions: ["A", "B"], isUserExtensible: false)
        let cat = try store.createCategory(name: "Widget")
        let def = PropertyDefinition(name: "Choice", type: .comboList(list), isRequired: false)
        let asset = try store.createAsset(name: "Item", categoryID: cat.id)

        XCTAssertThrowsError(try store.addCustomProperty(definition: def, value: .text("C"), toAssetID: asset.id))
    }

    func testAddRemoveUserOptionSucceedsOnNonExtensibleList() throws {
        let list = store.createComboList(name: "Fixed", systemOptions: ["A"], isUserExtensible: false)

        try store.addUserOption("B", toComboListID: list.id)
        XCTAssertTrue(list.userOptions.contains("B"))

        try store.removeUserOption("B", fromComboListID: list.id)
        XCTAssertFalse(list.userOptions.contains("B"))
    }

    func testRemoveSystemOptionThrows() throws {
        let list = store.createComboList(name: "Fixed", systemOptions: ["A"], isUserExtensible: true)
        XCTAssertThrowsError(try store.removeUserOption("A", fromComboListID: list.id)) { error in
            XCTAssertEqual(error as? AssetStoreError, .cannotModifySystemOption(listID: list.id, option: "A"))
        }
    }

    // MARK: - Name availability

    func testComboListNameIsAvailable() throws {
        let list = store.createComboList(name: "Materials")
        XCTAssertFalse(store.comboListNameIsAvailable("materials"))
        XCTAssertTrue(store.comboListNameIsAvailable("materials", excluding: list.id))
        XCTAssertTrue(store.comboListNameIsAvailable("Colors"))
    }

    // MARK: - ComboListField.matches (pure function)

    func testComboListFieldMatchesEmptyDraftReturnsAllOptions() {
        let list = ComboListDefinition(name: "Materials", systemOptions: ["Wood", "Metal", "Plastic"])
        XCTAssertEqual(ComboListField.matches(for: "", in: list), ["Wood", "Metal", "Plastic"])
    }

    func testComboListFieldMatchesFiltersCaseInsensitively() {
        let list = ComboListDefinition(name: "Materials", systemOptions: ["Wood", "Metal", "Plastic"])
        XCTAssertEqual(ComboListField.matches(for: "me", in: list), ["Metal"])
    }

    func testComboListFieldMatchesReturnsEmptyOnExactSingleMatch() {
        let list = ComboListDefinition(name: "Materials", systemOptions: ["Wood"])
        XCTAssertEqual(ComboListField.matches(for: "Wood", in: list), [])
    }

    func testComboListFieldMatchesCapsAtTen() {
        let options = (1...15).map { "Option \($0)" }
        let list = ComboListDefinition(name: "Many", systemOptions: options)
        XCTAssertEqual(ComboListField.matches(for: "", in: list).count, 10)
    }
}
