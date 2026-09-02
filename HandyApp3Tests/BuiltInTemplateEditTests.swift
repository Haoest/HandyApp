import XCTest
@testable import HandyApp3

/// Covers the gap `BuiltInCategoryUpgradeTests` left open: a user edit to a built-in template
/// field's *definition* (rename, Required toggle, type change) must survive
/// `upgradeBuiltInCategories()`, not just its value. See `AssetProperty.isUserEdited` and the
/// doc comment on `upgradeBuiltInCategories`.
final class BuiltInTemplateEditTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    private var automobileID: UUID { BuiltInTypes.deterministicID("category.\(SystemCategory.automobile.rawValue)") }
    private var makeFieldID: UUID { BuiltInTypes.deterministicID("field.automobile.Make") }

    /// A freshly-seeded Automobile category, exactly as `seedBuiltInCategories` would build it —
    /// every canonical field present and unedited.
    private func seedAutomobile() throws -> AssetCategory {
        let defs = BuiltInTypes.categoryTemplates[.automobile]!
        let templates = defs.map { AssetProperty(id: $0.definition.id, definition: $0.definition, sortOrder: $0.sortOrder) }
        return try store.createCategory(id: automobileID, name: SystemCategory.automobile.rawValue, propertyTemplates: templates)
    }

    // MARK: - A user edit survives the upgrade

    func testRenamedFieldSurvivesUpgrade() throws {
        let cat = try seedAutomobile()
        try store.updateTemplateProperty(id: makeFieldID, inCategoryID: cat.id, name: "Manufacturer")

        let changed = store.upgradeBuiltInCategories()

        let field = try XCTUnwrap(cat.propertyTemplates.first { $0.id == makeFieldID })
        XCTAssertEqual(field.definition.name, "Manufacturer", "a user rename must not be reverted to canonical")
        XCTAssertEqual(changed, 0)
    }

    func testRequiredToggleSurvivesUpgrade() throws {
        let cat = try seedAutomobile()
        XCTAssertTrue(cat.propertyTemplates.first { $0.id == makeFieldID }!.definition.isRequired)
        try store.updateTemplateProperty(id: makeFieldID, inCategoryID: cat.id, isRequired: false)

        store.upgradeBuiltInCategories()

        let field = try XCTUnwrap(cat.propertyTemplates.first { $0.id == makeFieldID })
        XCTAssertFalse(field.definition.isRequired, "a user Required toggle must not be reverted to canonical")
    }

    func testTypeChangeAndDefaultValueSurviveUpgrade() throws {
        let cat = try seedAutomobile()
        try store.updateTemplateProperty(id: makeFieldID, inCategoryID: cat.id, type: .basic(.number))
        let field = try XCTUnwrap(cat.propertyTemplates.first { $0.id == makeFieldID })
        field.value = .number(4)

        store.upgradeBuiltInCategories()

        XCTAssertEqual(field.definition.type, .basic(.number), "a user type change must not be reverted to canonical")
        XCTAssertEqual(field.value, .number(4), "the upgrade pass must not clear a value on a field it left alone")
    }

    // MARK: - Untouched fields keep receiving canonical upgrades

    func testUntouchedFieldStillReceivesCanonicalUpgrade() throws {
        let cat = try seedAutomobile()
        let field = try XCTUnwrap(cat.propertyTemplates.first { $0.id == makeFieldID })
        // Simulate an install that seeded before a canonical maxLength change shipped, without
        // going through updateTemplateProperty (so isUserEdited stays false, as a real stale
        // install would be).
        field.definition.maxLength = 20
        field.touch()

        let changed = store.upgradeBuiltInCategories()

        let upgraded = try XCTUnwrap(cat.propertyTemplates.first { $0.id == makeFieldID })
        XCTAssertEqual(upgraded.definition.maxLength, 40, "an untouched field must still pick up a canonical change")
        XCTAssertEqual(changed, 1)
    }

    // MARK: - Persistence and sync

    func testIsUserEditedSurvivesSaveAndLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = dir
        defer {
            AssetStore.baseDirOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        let cat = try seedAutomobile()
        try store.updateTemplateProperty(id: makeFieldID, inCategoryID: cat.id, name: "Manufacturer")
        store.save()

        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())
        let field = try XCTUnwrap(reloaded.categories[automobileID]?.propertyTemplates.first { $0.id == makeFieldID })
        XCTAssertTrue(field.isUserEdited)
        XCTAssertEqual(field.definition.name, "Manufacturer")
    }

    /// `SnapshotReconciler.joinAssetProperty` ORs `isUserEdited` across peers regardless of
    /// which side's `modifyDate` wins — a peer that hasn't heard about the rename yet, and
    /// whose own edit is newer, must not clear the flag back to false.
    func testIsUserEditedMergesAsOrRegardlessOfWhichSideWins() {
        let older = Date(timeIntervalSince1970: 0)
        let newer = Date(timeIntervalSince1970: 1000)
        let textType = PropertyTypeDTO(kind: .basic, basicType: .text, typeID: nil)
        let editedDef = PropertyDefinitionDTO(id: makeFieldID, name: "Manufacturer", type: textType, isRequired: true, maxLength: 40)
        let plainDef = PropertyDefinitionDTO(id: makeFieldID, name: "Make", type: textType, isRequired: true, maxLength: 40)

        let userEditedButOlder = AssetPropertyDTO(id: makeFieldID, definition: editedDef, value: nil, sortOrder: 0,
                                                   modifyDate: older, isDeleted: false, deletedAt: nil, isUserEdited: true)
        let plainButNewer = AssetPropertyDTO(id: makeFieldID, definition: plainDef, value: nil, sortOrder: 0,
                                              modifyDate: newer, isDeleted: false, deletedAt: nil, isUserEdited: false)

        let joined = SnapshotReconciler.joinAssetProperty(userEditedButOlder, plainButNewer)
        XCTAssertEqual(joined.definition.name, "Make", "whole-record LWW still picks the newer side's definition")
        XCTAssertTrue(joined.isUserEdited == true, "but the flag itself must survive the merge regardless of which side won")
    }

    // MARK: - Label rendering after a full seed -> upgrade -> render cycle

    func testLocalizedSeedNameReturnsUserRenameAfterUpgrade() throws {
        let cat = try seedAutomobile()
        try store.updateTemplateProperty(id: makeFieldID, inCategoryID: cat.id, name: "Manufacturer")
        store.upgradeBuiltInCategories()

        let field = try XCTUnwrap(cat.propertyTemplates.first { $0.id == makeFieldID })
        XCTAssertEqual(
            BuiltInTypes.localizedSeedName(id: field.definition.id, currentName: field.definition.name),
            "Manufacturer",
            "a rename that survived the upgrade must also read back as a rename, not the localized canonical label"
        )
    }
}
