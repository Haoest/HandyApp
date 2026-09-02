import XCTest
@testable import HandyApp3

final class SpotlightRecordTests: XCTestCase {

    var store: AssetStore!
    var categoryID: UUID!

    override func setUp() {
        super.setUp()
        store = AssetStore()
        categoryID = try! store.createCategory(name: "Vehicles").id
    }

    private func records() -> [SpotlightRecord] {
        SpotlightRecord.records(from: store.allAssets)
    }

    func testCarriesNameAndCategory() throws {
        try store.createAsset(name: "Testarossa 85", categoryID: categoryID)

        let record = try XCTUnwrap(records().first)

        XCTAssertEqual(record.name, "Testarossa 85")
        XCTAssertEqual(record.categoryName, "Vehicles")
    }

    func testIdentifierIsTheAssetID() throws {
        let asset = try store.createAsset(name: "Camry", categoryID: categoryID)

        XCTAssertEqual(records().first?.id, asset.id)
    }

    func testEmptyStoreProducesNoRecords() {
        XCTAssertTrue(records().isEmpty)
    }

    func testSoftDeletedAssetIsNotIndexed() throws {
        let keep = try store.createAsset(name: "Camry", categoryID: categoryID)
        let drop = try store.createAsset(name: "Civic", categoryID: categoryID)

        try store.softDeleteAsset(id: drop.id)

        XCTAssertEqual(records().map(\.id), [keep.id])
    }

    func testRestoredAssetIsIndexedAgain() throws {
        let asset = try store.createAsset(name: "Camry", categoryID: categoryID)
        try store.softDeleteAsset(id: asset.id)
        try store.restoreAsset(id: asset.id)

        XCTAssertEqual(records().map(\.id), [asset.id])
    }

    func testPurgedAssetIsNotIndexed() throws {
        let asset = try store.createAsset(name: "Camry", categoryID: categoryID)

        try store.hardDeleteAsset(id: asset.id)

        XCTAssertTrue(records().isEmpty)
    }

    /// A blank name would index as a row with nothing to tap on in Spotlight.
    func testBlankNameIsSkipped() throws {
        try store.createAsset(name: "   ", categoryID: categoryID)
        let named = try store.createAsset(name: "Camry", categoryID: categoryID)

        XCTAssertEqual(records().map(\.id), [named.id])
    }

    func testRenameIsReflected() throws {
        let asset = try store.createAsset(name: "Camry", categoryID: categoryID)

        try store.updateAsset(id: asset.id, name: "Camry Hybrid")

        XCTAssertEqual(records().first?.name, "Camry Hybrid")
    }
}
