import XCTest
@testable import HandyApp3

/// Coverage for `AssetStore.applyInPlace(_:)` — the identity-preserving apply used by the cloud
/// sync path. Unlike `applySnapshot` (used by `load()`), it must mutate existing live objects
/// rather than replace them, so open SwiftUI views holding a reference keep working, and it
/// must never remove anything for mere absence in the incoming snapshot.
final class ApplyInPlaceTests: XCTestCase {

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

    // MARK: - DTO builders (mirrors SnapshotReconcilerTests)

    private func property(id: UUID = UUID(), name: String = "Prop", value: StoredValueDTO? = nil,
                          sortOrder: Double = 0, modifyDate: Date? = Date()) -> AssetPropertyDTO {
        AssetPropertyDTO(id: id, definition: PropertyDefinitionDTO(
            id: UUID(), name: name, type: PropertyTypeDTO(kind: .basic, basicType: .text, typeID: nil), isRequired: false),
            value: value, sortOrder: sortOrder, modifyDate: modifyDate, isDeleted: false, deletedAt: nil)
    }

    private func categoryDTO(
        id: UUID, name: String = "Cat", propertyTemplates: [AssetPropertyDTO] = [],
        isDeleted: Bool = false, deletedAt: Date? = nil, isPurged: Bool? = nil
    ) -> CategoryDTO {
        CategoryDTO(id: id, name: name, iconName: "tray", propertyTemplates: propertyTemplates,
                   isDeleted: isDeleted, deletedAt: deletedAt, modifyDate: Date(), isPurged: isPurged)
    }

    private func assetDTO(
        id: UUID, name: String = "Asset", categoryID: UUID, parentID: UUID? = nil,
        isDeleted: Bool = false, deletedAt: Date? = nil,
        baseProperties: [AssetPropertyDTO] = [], photos: [PhotoDTO] = [],
        headModifyDate: Date = Date(), parentageModifyDate: Date = Date(), isPurged: Bool? = nil
    ) -> AssetDTO {
        AssetDTO(id: id, name: name, categoryID: categoryID, baseProperties: baseProperties,
                customProperties: [], photos: photos, events: [], transactions: [],
                parentID: parentID, isDeleted: isDeleted, deletedAt: deletedAt,
                createdDate: Date(), modifiedDate: Date(),
                parentageModifyDate: parentageModifyDate, headModifyDate: headModifyDate, isPurged: isPurged)
    }

    private func snapshot(categories: [CategoryDTO] = [], assets: [AssetDTO] = []) -> StoreSnapshotDTO {
        StoreSnapshotDTO(schemaVersion: storeSchemaVersion, compositeTypes: [], comboLists: [],
                        categories: categories, assets: assets, activityLog: [],
                        backgroundTheme: BackgroundTheme.mist.rawValue)
    }

    // MARK: - Identity preservation

    func testExistingAssetObjectIdentityIsPreserved() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let asset = try store.createAsset(name: "Car", categoryID: cat.id)

        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)],
                            assets: [assetDTO(id: asset.id, name: "Renamed", categoryID: cat.id)])
        store.applyInPlace(snap)

        XCTAssertTrue(store.assets[asset.id] === asset, "applyInPlace must mutate the existing object, not replace it")
        XCTAssertEqual(asset.name, "Renamed")
    }

    func testExistingCategoryObjectIdentityIsPreserved() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: "Renamed")])
        store.applyInPlace(snap)

        XCTAssertTrue(store.categories[cat.id] === cat)
        XCTAssertEqual(cat.name, "Renamed")
    }

    func testExistingAssetPropertyObjectIdentityIsPreserved() throws {
        let cat = try store.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text))),
        ])
        let asset = try store.createAsset(name: "Car", categoryID: cat.id)
        let prop = asset.baseProperties[0]

        let updatedProp = property(id: prop.id, name: "Make", value: .text("Toyota"), modifyDate: Date().addingTimeInterval(10))
        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)],
                            assets: [assetDTO(id: asset.id, categoryID: cat.id, baseProperties: [updatedProp])])
        store.applyInPlace(snap)

        XCTAssertTrue(asset.baseProperties[0] === prop)
        XCTAssertEqual(prop.value, .text("Toyota"))
    }

    // MARK: - New-record insertion

    func testUnknownAssetIsInsertedAsNew() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let newID = UUID()
        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)],
                            assets: [assetDTO(id: newID, name: "New Asset", categoryID: cat.id)])
        store.applyInPlace(snap)

        let inserted = try XCTUnwrap(store.assets[newID])
        XCTAssertEqual(inserted.name, "New Asset")
    }

    func testUnknownCategoryIsInsertedAsNew() throws {
        let newID = UUID()
        let snap = snapshot(categories: [categoryDTO(id: newID, name: "Brand New")])
        store.applyInPlace(snap)
        XCTAssertEqual(store.categories[newID]?.name, "Brand New")
    }

    // MARK: - Absence never deletes

    func testAssetNotInIncomingSnapshotIsNotRemoved() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let asset = try store.createAsset(name: "Car", categoryID: cat.id)

        // Empty incoming snapshot — as would happen merging against a peer that has nothing yet.
        store.applyInPlace(snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)], assets: []))

        XCTAssertNotNil(store.assets[asset.id], "applyInPlace must never remove a record for mere absence")
    }

    // MARK: - Hierarchy rewiring

    func testHierarchyIsRewiredWhenParentIDChanges() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let parent1 = try store.createAsset(name: "P1", categoryID: cat.id)
        let parent2 = try store.createAsset(name: "P2", categoryID: cat.id)
        let child = try store.createAsset(name: "Child", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent1.id)
        XCTAssertTrue(child.parent === parent1)

        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)], assets: [
            assetDTO(id: parent1.id, name: "P1", categoryID: cat.id),
            assetDTO(id: parent2.id, name: "P2", categoryID: cat.id),
            assetDTO(id: child.id, name: "Child", categoryID: cat.id, parentID: parent2.id,
                    parentageModifyDate: Date().addingTimeInterval(100)),
        ])
        store.applyInPlace(snap)

        XCTAssertTrue(child.parent === parent2, "child must be re-wired to its new merged parent")
        XCTAssertFalse(parent1.children.contains { $0.id == child.id })
        XCTAssertTrue(parent2.children.contains { $0.id == child.id })
    }

    func testAlreadyCorrectHierarchyIsNotChurned() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let parent = try store.createAsset(name: "P", categoryID: cat.id)
        let child = try store.createAsset(name: "Child", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)
        let stampBefore = child.parentageModifyDate

        // Snapshot describes exactly the current live state — same parentID.
        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)], assets: [
            assetDTO(id: parent.id, name: "P", categoryID: cat.id),
            assetDTO(id: child.id, name: "Child", categoryID: cat.id, parentID: parent.id,
                    parentageModifyDate: stampBefore),
        ])
        store.applyInPlace(snap)

        XCTAssertTrue(child.parent === parent, "no-op apply must not disturb an already-correct link")
        XCTAssertEqual(parent.children.count, 1)
    }

    // MARK: - Live/deleted boundary repair

    func testLiveChildIsDetachedFromNewlyDeletedParent() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let parent = try store.createAsset(name: "P", categoryID: cat.id)
        let child = try store.createAsset(name: "Child", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)

        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)], assets: [
            assetDTO(id: parent.id, name: "P", categoryID: cat.id, isDeleted: true, deletedAt: Date(),
                    headModifyDate: Date().addingTimeInterval(100)),
            assetDTO(id: child.id, name: "Child", categoryID: cat.id, parentID: parent.id),
        ])
        store.applyInPlace(snap)

        XCTAssertTrue(parent.isDeleted)
        XCTAssertFalse(child.isDeleted)
        XCTAssertNil(child.parent, "a live child must be detached from a parent that just became deleted")
    }

    // MARK: - Purge (isPurged)

    func testIncomingPurgedAssetReplacesRatherThanAdditivelyMergesLocalContent() throws {
        // The additive-only upsertX helpers applyInPlace normally uses for an existing asset
        // would never clear content this device still holds locally if a stripped incoming
        // DTO were run through them — this is the case that makes applyInPlace call
        // `purgeInPlace` instead when the incoming record is purged.
        let cat = try store.createCategory(name: "Vehicle")
        let asset = try store.createAsset(name: "Car", categoryID: cat.id)
        _ = try store.addPhoto(imageData: Data("full".utf8), thumbnailData: Data("thumb".utf8), toAssetID: asset.id)
        XCTAssertFalse(asset.photos.isEmpty, "sanity check")

        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)], assets: [
            assetDTO(id: asset.id, name: "Car", categoryID: cat.id, isDeleted: true, deletedAt: Date(),
                    headModifyDate: Date().addingTimeInterval(100), isPurged: true),
        ])
        store.applyInPlace(snap)

        XCTAssertTrue(store.assets[asset.id] === asset, "still the same object — mutated, not replaced")
        XCTAssertTrue(asset.isPurged)
        XCTAssertTrue(asset.photos.isEmpty, "purge must replace local content, not additively keep it")
        XCTAssertEqual(asset.name, "Car")
    }

    func testNewlyInsertedPurgedAssetWithDanglingCategoryNeverExposesARecoveredCategory() throws {
        // A live asset with a dangling categoryID resurrects a visible "Recovered" placeholder
        // (see testUnknownAssetIsInsertedAsNew's sibling coverage in StoreIntegrityTests) — a
        // purged one must not, since nothing displays a purged tombstone.
        let missingCategoryID = UUID()
        let newID = UUID()
        let snap = snapshot(assets: [
            assetDTO(id: newID, name: "Ghost", categoryID: missingCategoryID, isDeleted: true, isPurged: true),
        ])
        store.applyInPlace(snap)

        let inserted = try XCTUnwrap(store.assets[newID])
        XCTAssertTrue(inserted.isPurged)
        XCTAssertEqual(inserted.category.id, missingCategoryID, "categoryID round-trips even though no category exists")
        XCTAssertNil(store.categories[missingCategoryID], "a purged asset's recovery placeholder must never be committed to categories")

        // Round-trips with the original categoryID intact — buildSnapshot mustn't rewrite it.
        let reencoded = store.buildSnapshot()
        XCTAssertEqual(reencoded.assets.first { $0.id == newID }?.categoryID, missingCategoryID)
    }

    func testIncomingPurgedCategoryReplacesRatherThanAdditivelyMergesLocalContent() throws {
        // Mirrors testIncomingPurgedAssetReplacesRatherThanAdditivelyMergesLocalContent: the
        // additive-only upsertAssetProperties applyInPlace normally uses for an existing
        // category's templates would never clear content this device still holds locally if a
        // stripped incoming DTO were run through it — this is the case that makes applyInPlace
        // call `purgeCategoryInPlace` instead when the incoming record is purged.
        let cat = try store.createCategory(name: "Appliances", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Brand", type: .basic(.text))),
        ])
        XCTAssertFalse(cat.propertyTemplates.isEmpty, "sanity check")

        let snap = snapshot(categories: [
            categoryDTO(id: cat.id, name: "", isDeleted: true, deletedAt: Date(), isPurged: true),
        ])
        store.applyInPlace(snap)

        XCTAssertTrue(store.categories[cat.id] === cat, "still the same object — mutated, not replaced")
        XCTAssertTrue(cat.isPurged)
        XCTAssertTrue(cat.propertyTemplates.isEmpty, "purge must replace local content, not additively keep it")
        XCTAssertEqual(cat.name, "")
    }

    /// Pins the fix to a real bug: `applyInPlace`'s existing-record branch used to never assign
    /// `existing.isPurged` at all, so a merged snapshot that un-purges a record (the new
    /// `SnapshotReconciler` gate can do this — see `joinAsset`'s doc comment) would leave this
    /// device's copy stuck `isPurged == true` forever, hidden from `allAssets`, even though the
    /// merge result says it's live again.
    func testIncomingUnPurgedAssetClearsIsPurgedAndRefillsContent() throws {
        let cat = try store.createCategory(name: "Vehicle")
        let asset = try store.createAsset(name: "Car", categoryID: cat.id)
        store.purgeInPlace(asset)
        XCTAssertTrue(asset.isPurged, "sanity check")
        XCTAssertNotNil(asset.purgedAt, "sanity check")

        let snap = snapshot(categories: [categoryDTO(id: cat.id, name: cat.name)], assets: [
            assetDTO(id: asset.id, name: "Car", categoryID: cat.id, isDeleted: false,
                    baseProperties: [property(name: "Color")], isPurged: false),
        ])
        store.applyInPlace(snap)

        XCTAssertTrue(store.assets[asset.id] === asset, "still the same object — mutated, not replaced")
        XCTAssertFalse(asset.isPurged)
        XCTAssertNil(asset.purgedAt)
        XCTAssertFalse(store.allAssets.isEmpty, "an un-purged asset must be visible again")
        XCTAssertEqual(asset.baseProperties.count, 1, "content must be refilled from the merged snapshot")
    }

    /// Category twin of `testIncomingUnPurgedAssetClearsIsPurgedAndRefillsContent`.
    func testIncomingUnPurgedCategoryClearsIsPurgedAndRestoresName() throws {
        let cat = try store.createCategory(name: "Appliances")
        store.purgeCategoryInPlace(cat)
        XCTAssertTrue(cat.isPurged, "sanity check")
        XCTAssertEqual(cat.name, "", "sanity check")

        let snap = snapshot(categories: [
            categoryDTO(id: cat.id, name: "Appliances",
                       propertyTemplates: [property(name: "Brand")], isDeleted: false, isPurged: false),
        ])
        store.applyInPlace(snap)

        XCTAssertTrue(store.categories[cat.id] === cat, "still the same object — mutated, not replaced")
        XCTAssertFalse(cat.isPurged)
        XCTAssertNil(cat.purgedAt)
        XCTAssertEqual(cat.name, "Appliances", "name must be restored, not left blanked")
        XCTAssertEqual(cat.propertyTemplates.count, 1)
    }

    // MARK: - No-op self-merge produces zero churn

    func testApplyingCurrentStateBackToItselfChangesNothingObservable() throws {
        let cat = try store.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text))),
        ])
        let asset = try store.createAsset(name: "Car", categoryID: cat.id)
        try store.setPropertyValue(.text("Toyota"), forDefinitionID: asset.baseProperties[0].definition.id, onAssetID: asset.id)

        let snap = snapshot(categories: [
            categoryDTO(id: cat.id, name: cat.name, propertyTemplates: [
                property(id: cat.propertyTemplates[0].id, name: "Make", modifyDate: cat.propertyTemplates[0].modifyDate),
            ]),
        ], assets: [
            assetDTO(id: asset.id, name: asset.name, categoryID: cat.id,
                    baseProperties: [property(id: asset.baseProperties[0].id, name: "Make", value: .text("Toyota"),
                                             modifyDate: asset.baseProperties[0].modifyDate)],
                    headModifyDate: asset.headModifyDate, parentageModifyDate: asset.parentageModifyDate),
        ])
        store.applyInPlace(snap)

        XCTAssertEqual(asset.name, "Car")
        XCTAssertEqual(asset.baseProperties[0].value, .text("Toyota"))
        XCTAssertEqual(store.assets.count, 1)
        XCTAssertEqual(store.categories.count, 1)
    }
}
