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
}
