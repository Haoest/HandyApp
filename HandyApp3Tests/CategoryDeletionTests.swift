import XCTest
@testable import HandyApp3

final class CategoryDeletionTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    private func makeCategory(name: String = "Test") throws -> AssetCategory {
        try store.createCategory(name: name)
    }

    // MARK: - associatedAssetCount

    func testAssociatedAssetCountIsZeroForEmptyCategory() throws {
        let cat = try makeCategory()
        XCTAssertEqual(store.associatedAssetCount(categoryID: cat.id), 0)
    }

    func testAssociatedAssetCountIncludesLiveAssets() throws {
        let cat = try makeCategory()
        try store.createAsset(name: "Asset A", categoryID: cat.id)
        try store.createAsset(name: "Asset B", categoryID: cat.id)
        XCTAssertEqual(store.associatedAssetCount(categoryID: cat.id), 2)
    }

    func testAssociatedAssetCountIncludesSoftDeletedAssets() throws {
        let cat = try makeCategory()
        let a1 = try store.createAsset(name: "Asset A", categoryID: cat.id)
        try store.createAsset(name: "Asset B", categoryID: cat.id)
        try store.softDeleteAsset(id: a1.id)
        // Still 2 — soft-deleted assets keep the category alive in the purge guard.
        XCTAssertEqual(store.associatedAssetCount(categoryID: cat.id), 2)
    }

    // MARK: - softDeleteCategory

    func testSoftDeleteCategorySetsFlags() throws {
        let cat = try makeCategory()
        let before = Date()
        try store.softDeleteCategory(id: cat.id)
        XCTAssertTrue(cat.isDeleted)
        XCTAssertNotNil(cat.deletedAt)
        XCTAssertGreaterThanOrEqual(cat.deletedAt!, before)
        XCTAssertLessThanOrEqual(cat.deletedAt!, Date())
    }

    func testSoftDeleteCategoryMovesFromAllToDeleted() throws {
        let cat = try makeCategory()
        try store.softDeleteCategory(id: cat.id)
        XCTAssertFalse(store.allCategories.contains { $0.id == cat.id })
        XCTAssertTrue(store.deletedCategories.contains { $0.id == cat.id })
    }

    // MARK: - purgeHardDeleted

    func testPurgeRemovesUnreferencedCategoryPastRetention() throws {
        let cat = try makeCategory()
        try store.softDeleteCategory(id: cat.id)
        // Backdate modifyDate along with deletedAt — AssetCategory.isProtectedFromAutoPurge
        // (mirroring SnapshotReconciler's sync-merge gate) refuses to purge a category whose
        // own content is newer than its delete decision; leaving modifyDate at "now" would make
        // this look like an edit after the delete and the purge below would be refused.
        let backdate = Date().addingTimeInterval(-15 * 86_400) // 15 days ago
        cat.deletedAt = backdate
        cat.modifyDate = backdate
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
        XCTAssertFalse(store.deletedCategories.contains { $0.id == cat.id })
        // The record survives as a minimal tombstone — never removed, so a peer that still
        // holds the full category can't resurrect it on the next sync.
        XCTAssertNotNil(store.categories[cat.id])
        XCTAssertTrue(store.categories[cat.id]?.isPurged ?? false)
        XCTAssertEqual(store.categories[cat.id]?.name, "")
        XCTAssertEqual(store.categories[cat.id]?.iconName, "")
    }

    /// The headline new behavior: an aged tombstone whose content was edited AFTER the delete
    /// decision must not be silently stripped by the automatic retention sweep — it stays a
    /// live tombstone (visible in Trash) indefinitely, restorable or removable via an explicit
    /// "delete now", rather than losing that edit the moment the retention window elapses.
    func testPurgeSkipsCategoryEditedAfterDeletion() throws {
        let cat = try makeCategory()
        try store.softDeleteCategory(id: cat.id)
        cat.deletedAt = Date().addingTimeInterval(-15 * 86_400) // 15 days ago, past retention
        cat.modifyDate = Date() // edited just now — after the delete decision
        XCTAssertTrue(cat.isProtectedFromAutoPurge, "sanity check")

        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertTrue(store.deletedCategories.contains { $0.id == cat.id },
                      "an edited-after-delete category must not be auto-purged despite being past retention")
        XCTAssertFalse(cat.isPurged)
    }

    /// Explicit user intent ("delete now") is unconditional and must strip the category
    /// regardless of `isProtectedFromAutoPurge` — only the AUTOMATIC sweep is gated.
    func testHardDeleteCategoryIgnoresAutoPurgeProtection() throws {
        let cat = try makeCategory()
        try store.softDeleteCategory(id: cat.id)
        cat.deletedAt = Date().addingTimeInterval(-15 * 86_400)
        cat.modifyDate = Date()
        XCTAssertTrue(cat.isProtectedFromAutoPurge, "sanity check")

        try store.hardDeleteCategory(id: cat.id)

        XCTAssertTrue(cat.isPurged, "an explicit delete-now must strip regardless of protection")
    }

    func testPurgeKeepsUnreferencedCategoryWithinRetention() throws {
        let cat = try makeCategory()
        try store.softDeleteCategory(id: cat.id)
        cat.deletedAt = Date().addingTimeInterval(-5 * 86_400) // 5 days ago
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
        XCTAssertTrue(store.deletedCategories.contains { $0.id == cat.id })
    }

    func testPurgeKeepsCategoryReferencedByLiveAsset() throws {
        let cat = try makeCategory()
        try store.createAsset(name: "Asset A", categoryID: cat.id)
        try store.softDeleteCategory(id: cat.id)
        cat.deletedAt = Date().addingTimeInterval(-15 * 86_400)
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
        XCTAssertTrue(store.deletedCategories.contains { $0.id == cat.id })
    }

    func testPurgeKeepsCategoryReferencedBySoftDeletedAsset() throws {
        let cat = try makeCategory()
        let asset = try store.createAsset(name: "Asset A", categoryID: cat.id)
        try store.softDeleteAsset(id: asset.id)
        try store.softDeleteCategory(id: cat.id)
        cat.deletedAt = Date().addingTimeInterval(-15 * 86_400)
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
        // The soft-deleted asset still references the category — must survive.
        XCTAssertTrue(store.deletedCategories.contains { $0.id == cat.id })
    }

    func testPurgeCategoryOnceReferringAssetAlsoPurged() throws {
        // A category kept alive only by a soft-deleted asset should be purged in the same
        // sweep once that asset's retention also expires — a purged asset no longer counts
        // as a reference, even though its (now-minimal) record is never removed.
        let cat = try makeCategory()
        let asset = try store.createAsset(name: "Asset A", categoryID: cat.id)
        try store.softDeleteAsset(id: asset.id)
        // Backdate content stamps along with deletedAt on both records — see the identical
        // comment in testPurgeRemovesUnreferencedCategoryPastRetention. Without backdating the
        // asset's own modifiedDate/headModifyDate, it stays un-purged (protected), which would
        // also keep it counted as a live reference to the category, independently blocking the
        // category purge this test is actually about.
        let backdate = Date().addingTimeInterval(-15 * 86_400) // expired
        asset.deletedAt = backdate
        asset.modifiedDate = backdate
        asset.headModifyDate = backdate
        try store.softDeleteCategory(id: cat.id)
        cat.deletedAt = backdate
        cat.modifyDate = backdate

        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertFalse(store.deletedAssets.contains { $0.id == asset.id },
                       "purged asset must drop out of the deletedAssets list")
        XCTAssertNotNil(store.assets[asset.id], "the asset record itself must survive purge")
        XCTAssertTrue(store.assets[asset.id]?.isPurged ?? false)
        XCTAssertFalse(store.deletedCategories.contains { $0.id == cat.id },
                       "category must be purged once its only referencing asset is purged")
    }

    // MARK: - purgeHardDeleted (asset protection)

    /// Asset twin of `testPurgeSkipsCategoryEditedAfterDeletion`.
    func testPurgeSkipsAssetEditedAfterDeletion() throws {
        let cat = try makeCategory()
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        try store.softDeleteAsset(id: asset.id)
        asset.deletedAt = Date().addingTimeInterval(-15 * 86_400) // past retention
        asset.modifiedDate = Date() // edited just now — after the delete decision
        asset.headModifyDate = Date()
        XCTAssertTrue(asset.isProtectedFromAutoPurge, "sanity check")

        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertTrue(store.deletedAssets.contains { $0.id == asset.id },
                      "an edited-after-delete asset must not be auto-purged despite being past retention")
        XCTAssertFalse(asset.isPurged)
    }

    // MARK: - hardDeleteAsset (immediate "Delete now" path)

    func testHardDeleteAssetPurgesSubtreeImmediately() throws {
        let cat = try makeCategory()
        let parent = try store.createAsset(name: "Parent", categoryID: cat.id)
        let child = try store.createAsset(name: "Child", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)
        try store.softDeleteAsset(id: parent.id)

        try store.hardDeleteAsset(id: parent.id)

        XCTAssertFalse(store.deletedAssets.contains { $0.id == parent.id })
        XCTAssertFalse(store.deletedAssets.contains { $0.id == child.id })
        // Records survive as minimal tombstones — never removed, so a peer can't resurrect them.
        XCTAssertNotNil(store.assets[parent.id])
        XCTAssertNotNil(store.assets[child.id])
        XCTAssertEqual(store.assets[parent.id]?.name, "Parent")
        XCTAssertTrue(store.assets[parent.id]?.isPurged ?? false)
        XCTAssertTrue(store.assets[child.id]?.isPurged ?? false)
        XCTAssertNil(store.assets[parent.id]?.parentID)
        XCTAssertNil(store.assets[child.id]?.parentID)
    }

    /// `purgeInPlace` strips content but deliberately leaves the tombstone alone, mirroring
    /// `SnapshotReconciler.stripPurged`. Purging straight from live must therefore stamp the
    /// tombstone itself, or the record would read as live-but-empty and stay in the asset list.
    func testHardDeleteOfLiveAssetTombstonesItAndHidesItEverywhere() throws {
        let cat = try makeCategory()
        let asset = try store.createAsset(name: "Mower", categoryID: cat.id)

        try store.hardDeleteAsset(id: asset.id)   // no softDeleteAsset first

        let purged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertTrue(purged.isPurged)
        XCTAssertTrue(purged.isDeleted, "a purged asset must carry a tombstone")
        XCTAssertNotNil(purged.deletedAt, "without deletedAt the reap sweep can never age it out")
        XCTAssertFalse(store.allAssets.contains { $0.id == asset.id },
                       "a purged asset has no content left and must never appear as live")
        XCTAssertFalse(store.deletedAssets.contains { $0.id == asset.id })
    }

    func testHardDeleteOfLiveCategoryTombstonesItAndHidesItEverywhere() throws {
        let cat = try makeCategory(name: "Appliances")

        try store.hardDeleteCategory(id: cat.id)   // no softDeleteCategory first

        let purged = try XCTUnwrap(store.categories[cat.id])
        XCTAssertTrue(purged.isPurged)
        XCTAssertTrue(purged.isDeleted, "a purged category must carry a tombstone")
        XCTAssertNotNil(purged.deletedAt)
        XCTAssertFalse(store.allCategories.contains { $0.id == cat.id },
                       "a purged category's name is blanked and must never appear as live")
        XCTAssertFalse(store.deletedCategories.contains { $0.id == cat.id })
    }

    /// Restoring can only clear a tombstone; it cannot bring content back. Mirrors the guard
    /// `restoreCategory` already had — only `importJSON` carries the content to undo a purge.
    func testRestoreAssetRefusesAPurgedRecord() throws {
        let cat = try makeCategory()
        let asset = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.softDeleteAsset(id: asset.id)
        try store.hardDeleteAsset(id: asset.id)

        try store.restoreAsset(id: asset.id)

        let still = try XCTUnwrap(store.assets[asset.id])
        XCTAssertTrue(still.isDeleted, "restore must not resurrect an emptied husk")
        XCTAssertTrue(still.isPurged)
        XCTAssertFalse(store.allAssets.contains { $0.id == asset.id })
    }

    // MARK: - hardDeleteCategory (immediate "Delete now" path)

    func testHardDeleteCategoryPurgesImmediately() throws {
        let cat = try makeCategory(name: "Appliances")
        try store.softDeleteCategory(id: cat.id)

        try store.hardDeleteCategory(id: cat.id)

        XCTAssertFalse(store.deletedCategories.contains { $0.id == cat.id })
        // Record survives as a minimal tombstone — never removed, so a peer can't resurrect it.
        XCTAssertNotNil(store.categories[cat.id])
        XCTAssertTrue(store.categories[cat.id]?.isPurged ?? false)
        XCTAssertEqual(store.categories[cat.id]?.name, "")
        XCTAssertTrue(store.categories[cat.id]?.propertyTemplates.isEmpty ?? false)
    }

    func testCreateCategoryAllowsNameReuseAfterPurge() throws {
        let cat = try makeCategory(name: "Appliances")
        try store.softDeleteCategory(id: cat.id)
        try store.hardDeleteCategory(id: cat.id)

        // A purged category's blanked "" name must never hold the original name hostage, and
        // the original name itself must be reusable once its category is purged.
        XCTAssertNoThrow(try store.createCategory(name: "Appliances"))
    }

    // MARK: - deleteCategory (hard delete — "Delete now" path)

    func testDeleteCategoryHardRemovesImmediately() throws {
        let cat = try makeCategory()
        try store.softDeleteCategory(id: cat.id)
        try store.deleteCategory(id: cat.id)
        XCTAssertFalse(store.allCategories.contains { $0.id == cat.id })
        XCTAssertFalse(store.deletedCategories.contains { $0.id == cat.id })
    }
}
