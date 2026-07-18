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
        cat.deletedAt = Date().addingTimeInterval(-15 * 86_400) // 15 days ago
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
        XCTAssertFalse(store.deletedCategories.contains { $0.id == cat.id })
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

    // MARK: - deleteCategory (hard delete — "Delete now" path)

    func testDeleteCategoryHardRemovesImmediately() throws {
        let cat = try makeCategory()
        try store.softDeleteCategory(id: cat.id)
        try store.deleteCategory(id: cat.id)
        XCTAssertFalse(store.allCategories.contains { $0.id == cat.id })
        XCTAssertFalse(store.deletedCategories.contains { $0.id == cat.id })
    }
}
