import XCTest
@testable import HandyApp3

/// Referential-integrity invariants between assets and their categories across
/// hard-purge and merge-on-import:
/// - `purgeHardDeleted` must not remove a soft-deleted category still referenced
///   by a live asset — that would leave the asset with a dangling categoryID.
/// - `importJSON` merges additively; an incoming asset whose category is absent
///   from the snapshot must still land (recovered under a placeholder category),
///   never silently dropped.
/// - The activity log must never reference an asset that didn't survive a merge.
final class StoreIntegrityTests: XCTestCase {

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

    // MARK: - Helpers

    /// Removes the category with the given id from an exported snapshot, leaving
    /// its assets in place — simulating the dangling references a hard-purged
    /// category leaves behind in older exports.
    private func stripCategory(id: UUID, fromExport data: Data) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var categories = try XCTUnwrap(json["categories"] as? [[String: Any]])
        let before = categories.count
        categories.removeAll { ($0["id"] as? String) == id.uuidString }
        XCTAssertEqual(categories.count, before - 1, "expected to strip exactly one category")
        json["categories"] = categories
        return try JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Bug #2: purge must not orphan live assets

    func testPurgeKeepsSoftDeletedCategoryStillReferencedByLiveAsset() throws {
        let category = try store.createCategory(name: "Appliances")
        let asset = try store.createAsset(name: "Fridge", categoryID: category.id)

        try store.softDeleteCategory(id: category.id)
        category.deletedAt = Date(timeIntervalSinceNow: -100 * 86_400)

        store.purgeHardDeleted(olderThan: 90 * 86_400)

        XCTAssertNotNil(
            store.categories[category.id],
            "a category still referenced by a live asset must survive the purge; removing it leaves the asset with a dangling categoryID that load/import will drop"
        )
        XCTAssertNotNil(store.assets[asset.id], "the live asset must be untouched by the purge")
    }

    func testPurgeRemovesSoftDeletedCategoryWithNoRemainingReferences() throws {
        let category = try store.createCategory(name: "Empty")
        try store.softDeleteCategory(id: category.id)
        // Backdate modifyDate along with deletedAt — AssetCategory.isProtectedFromAutoPurge
        // refuses to purge a category whose own content is newer than its delete decision;
        // leaving modifyDate at "now" would make this look like an edit after the delete and
        // the purge below would be refused.
        let backdate = Date(timeIntervalSinceNow: -100 * 86_400)
        category.deletedAt = backdate
        category.modifyDate = backdate

        store.purgeHardDeleted(olderThan: 90 * 86_400)

        let purged = try XCTUnwrap(
            store.categories[category.id],
            "the record must survive purge — see AssetCategory.isPurged — or a peer that still holds it would union it back on the next sync"
        )
        XCTAssertTrue(purged.isPurged)
        XCTAssertEqual(purged.name, "")
        XCTAssertEqual(purged.iconName, "")
        XCTAssertTrue(purged.propertyTemplates.isEmpty)
        XCTAssertFalse(store.deletedCategories.contains { $0.id == category.id },
                       "a purged category must not appear in the Deleted Categories list")
    }

    // MARK: - Merge must not silently drop orphaned assets

    func testImportPreservesAssetWhoseCategoryIsMissingFromSnapshot() throws {
        let keptCategory = try store.createCategory(name: "Kept")
        let missingCategory = try store.createCategory(name: "Missing")
        let keptAsset = try store.createAsset(name: "KeptAsset", categoryID: keptCategory.id)
        let orphanAsset = try store.createAsset(name: "OrphanAsset", categoryID: missingCategory.id)
        _ = try store.addEvent(title: "Checkup", date: Date(), toAssetID: orphanAsset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try stripCategory(id: missingCategory.id, fromExport: export)

        // Import into a second, empty store — merging the doctored file back into `store`
        // would pass vacuously since `store` still has the (undoctored) category locally.
        let tempDir2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir2
        let store2 = AssetStore()
        defer {
            AssetStore.baseDirOverride = tempDir
            try? FileManager.default.removeItem(at: tempDir2)
        }

        try store2.importJSON(data: doctored)

        XCTAssertNotNil(store2.assets[keptAsset.id], "asset with an intact category must survive import")
        XCTAssertNotNil(
            store2.assets[orphanAsset.id],
            "asset whose category is missing from the snapshot must be recovered, not silently dropped"
        )
    }

    func testImportedActivityLogOnlyReferencesAssetsThatSurvivedImport() throws {
        let category = try store.createCategory(name: "Vanishing")
        let survivor = try store.createAsset(name: "Fridge", categoryID: category.id)
        let skipped = try store.createAsset(name: "Trashed", categoryID: category.id)
        _ = try store.addEvent(title: "Checkup", date: Date(), toAssetID: survivor.id)
        _ = try store.addEvent(title: "Recall", date: Date(), toAssetID: skipped.id)
        try store.softDeleteAsset(id: skipped.id)

        let export = try XCTUnwrap(store.exportJSON())

        let tempDir2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir2
        let store2 = AssetStore()
        defer {
            AssetStore.baseDirOverride = tempDir
            try? FileManager.default.removeItem(at: tempDir2)
        }

        try store2.importJSON(data: export)

        XCTAssertNil(store2.assets[skipped.id], "soft-deleted incoming asset must be skipped by merge")
        for entry in store2.activityLog {
            let referenced = entry.owningAssetID ?? (entry.kind == .asset ? entry.recordID : nil)
            guard let assetID = referenced else { continue }
            XCTAssertNotNil(
                store2.assets[assetID],
                "activity entry (\(entry.kind)) references asset \(assetID) that merge skipped — log and assets must stay consistent"
            )
        }
    }

    // MARK: - Bug #3: import must be durable before returning

    func testImportIsOnDiskWhenCallReturns() throws {
        let unique = "Probe-" + UUID().uuidString.prefix(20) // stays under TextLimits.assetName (40)
        let category = try store.createCategory(name: "Garage")
        _ = try store.createAsset(name: unique, categoryID: category.id)
        let export = try XCTUnwrap(store.exportJSON())

        try store.importJSON(data: export)

        // Assert the invariant, not the on-disk layout: a completely fresh store, reading from
        // the same directory, must already see the probe asset. Reading AssetStore.storeURL's
        // bytes directly would only prove the manifest was written, not the asset shard.
        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())
        XCTAssertTrue(
            reloaded.allAssets.contains { $0.name == unique },
            "importJSON must persist synchronously — an async save lets a relaunch or cloud-monitor refresh resurrect the pre-import store"
        )
    }

    // MARK: - Control: a clean round-trip works today and must keep working

    func testImportOfUnmodifiedExportPreservesEverything() throws {
        let category = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: category.id)
        _ = try store.addEvent(title: "Oil change", date: Date(), toAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        try store.importJSON(data: export)

        XCTAssertNotNil(store.assets[asset.id])
        XCTAssertNotNil(store.categories[category.id])
        XCTAssertEqual(store.assets[asset.id]?.events.count, 1)
    }
}
