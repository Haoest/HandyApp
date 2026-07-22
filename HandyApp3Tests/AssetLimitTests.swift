import XCTest
@testable import HandyApp3

final class AssetLimitTests: XCTestCase {

    var store: AssetStore!
    var categoryID: UUID!

    override func setUp() {
        super.setUp()
        store = AssetStore()
        categoryID = try! store.createCategory(name: "Test").id
    }

    @discardableResult
    private func makeAsset(_ name: String = "Asset") throws -> Asset {
        try store.createAsset(name: name, categoryID: categoryID)
    }

    func testNoLimitByDefault() throws {
        for i in 0..<6 {
            try makeAsset("Asset \(i)")
        }
        XCTAssertEqual(store.allAssets.count, 6)
    }

    func testSixthCreateThrowsAtLimitFive() throws {
        store.assetCreationLimit = 5
        for i in 0..<5 {
            try makeAsset("Asset \(i)")
        }
        XCTAssertThrowsError(try makeAsset("Sixth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeLimitReached(limit: 5))
        }
    }

    func testSoftDeleteFreesSlotUnderLimit() throws {
        store.assetCreationLimit = 5
        var created: [Asset] = []
        for i in 0..<5 {
            created.append(try makeAsset("Asset \(i)"))
        }
        try store.softDeleteAsset(id: created[0].id)
        XCTAssertNoThrow(try makeAsset("Replacement"))
    }

    func testLiftingLimitUnblocksCreation() throws {
        store.assetCreationLimit = 5
        for i in 0..<5 {
            try makeAsset("Asset \(i)")
        }
        XCTAssertThrowsError(try makeAsset("Blocked"))
        store.assetCreationLimit = nil
        XCTAssertNoThrow(try makeAsset("Unblocked"))
    }

    func testCanCreateAssetTracksState() throws {
        store.assetCreationLimit = 5
        for i in 0..<4 {
            try makeAsset("Asset \(i)")
        }
        XCTAssertTrue(store.hasAssetCapacity)
        try makeAsset("Fifth")
        XCTAssertFalse(store.hasAssetCapacity)
        store.assetCreationLimit = nil
        XCTAssertTrue(store.hasAssetCapacity)
    }

    func testRestoreBlockedAtLimit() throws {
        store.assetCreationLimit = 5
        var created: [Asset] = []
        for i in 0..<5 {
            created.append(try makeAsset("Asset \(i)"))
        }
        try store.softDeleteAsset(id: created[0].id)
        try makeAsset("Backfill")
        XCTAssertThrowsError(try store.restoreAsset(id: created[0].id)) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeLimitReached(limit: 5))
        }
    }

    func testRestoreAllowedBelowLimit() throws {
        store.assetCreationLimit = 5
        var created: [Asset] = []
        for i in 0..<5 {
            created.append(try makeAsset("Asset \(i)"))
        }
        try store.softDeleteAsset(id: created[0].id)
        XCTAssertNoThrow(try store.restoreAsset(id: created[0].id))
        XCTAssertEqual(store.allAssets.count, 5)
    }

    func testRestoreSubtreeBlockedWhenFamilyExceedsLimit() throws {
        store.assetCreationLimit = 5
        // Build a 2-asset family (parent + child) and delete it first, so the live
        // count never exceeds the limit of 5 while setting up the scenario.
        let parent = try makeAsset("Parent")
        let child = try makeAsset("Child")
        try store.addChild(assetID: child.id, toParentID: parent.id)
        try store.softDeleteAsset(id: parent.id) // 0 live, 2 soft-deleted

        // Now fill 4 live slots.
        for i in 0..<4 { try makeAsset("Asset \(i)") } // 4 live remain

        // Restoring the 2-asset family would bring us to 6 > 5, so it must throw.
        XCTAssertFalse(store.hasCapacity(forAdditional: 2))
        XCTAssertThrowsError(try store.restoreAsset(id: parent.id)) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeLimitReached(limit: 5))
        }
    }

    func testRestoreSubtreeRestoresAllDescendants() throws {
        let parent = try makeAsset("Parent")
        let child = try makeAsset("Child")
        let grandchild = try makeAsset("Grandchild")
        try store.addChild(assetID: child.id, toParentID: parent.id)
        try store.addChild(assetID: grandchild.id, toParentID: child.id)

        try store.softDeleteAsset(id: parent.id)
        XCTAssertEqual(store.allAssets.count, 0)

        try store.restoreAsset(id: parent.id)
        XCTAssertEqual(store.allAssets.count, 3)
        XCTAssertFalse(parent.isDeleted)
        XCTAssertFalse(child.isDeleted)
        XCTAssertFalse(grandchild.isDeleted)
    }
}
