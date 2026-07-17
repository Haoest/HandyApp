import XCTest
@testable import HandyApp3

/// Referential-integrity invariants between assets and their categories across
/// hard-purge and export/import. These encode the *intended* behavior:
/// - Bug #1: `importJSON` silently drops assets whose category is missing from
///   the snapshot (`applySnapshot` guard), while keeping their activity entries.
/// - Bug #2: `purgeHardDeleted` removes a soft-deleted category even when live
///   assets still reference it, creating the dangling references Bug #1 then eats.
/// The bug tests FAIL against the current implementation by design; they go
/// green when the fixes land.
final class StoreIntegrityTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
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
        category.deletedAt = Date(timeIntervalSinceNow: -100 * 86_400)

        store.purgeHardDeleted(olderThan: 90 * 86_400)

        XCTAssertNil(
            store.categories[category.id],
            "an aged-out soft-deleted category with no referencing assets should still be purged"
        )
    }

    // MARK: - Bug #1: import must not silently drop orphaned assets

    func testImportPreservesAssetWhoseCategoryIsMissingFromSnapshot() throws {
        let keptCategory = try store.createCategory(name: "Kept")
        let missingCategory = try store.createCategory(name: "Missing")
        let keptAsset = try store.createAsset(name: "KeptAsset", categoryID: keptCategory.id)
        let orphanAsset = try store.createAsset(name: "OrphanAsset", categoryID: missingCategory.id)
        _ = try store.addEvent(title: "Checkup", date: Date(), toAssetID: orphanAsset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try stripCategory(id: missingCategory.id, fromExport: export)

        try store.importJSON(data: doctored)

        XCTAssertNotNil(store.assets[keptAsset.id], "asset with an intact category must survive import")
        XCTAssertNotNil(
            store.assets[orphanAsset.id],
            "asset whose category is missing from the snapshot must be recovered, not silently dropped"
        )
    }

    func testImportedActivityLogOnlyReferencesAssetsThatSurvivedImport() throws {
        let category = try store.createCategory(name: "Vanishing")
        let asset = try store.createAsset(name: "Fridge", categoryID: category.id)
        _ = try store.addEvent(title: "Checkup", date: Date(), toAssetID: asset.id)
        _ = try store.addTransaction(details: "Repair", amount: 42, date: Date(),
                                     kind: .expense, toAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try stripCategory(id: category.id, fromExport: export)

        try store.importJSON(data: doctored)

        for entry in store.activityLog {
            let referenced = entry.owningAssetID ?? (entry.kind == .asset ? entry.recordID : nil)
            guard let assetID = referenced else { continue }
            XCTAssertNotNil(
                store.assets[assetID],
                "activity entry (\(entry.kind)) references asset \(assetID) that import dropped — log and assets must stay consistent"
            )
        }
    }

    // MARK: - Bug #3: import must be durable before returning

    func testImportIsOnDiskWhenCallReturns() throws {
        let unique = "Probe-\(UUID().uuidString)"
        let category = try store.createCategory(name: "Garage")
        _ = try store.createAsset(name: unique, categoryID: category.id)
        let export = try XCTUnwrap(store.exportJSON())

        try store.importJSON(data: export)

        let disk = try Data(contentsOf: AssetStore.storeURL)
        let text = try XCTUnwrap(String(data: disk, encoding: .utf8))
        XCTAssertTrue(
            text.contains(unique),
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
