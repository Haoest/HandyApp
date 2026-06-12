import XCTest
@testable import HandyApp3

final class ActivityLogTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    private func makeCategory() throws -> AssetCategory {
        try store.createCategory(name: "Test")
    }

    func testCreateAssetLogsEntry() throws {
        let category = try makeCategory()
        let before = Date()
        let asset = try store.createAsset(name: "Camry", categoryID: category.id)

        XCTAssertEqual(store.activityLog.count, 1)
        let entry = try XCTUnwrap(store.activityLog.first)
        XCTAssertEqual(entry.kind, .asset)
        XCTAssertEqual(entry.recordID, asset.id)
        XCTAssertNil(entry.owningAssetID)
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, Date())
    }

    func testAddEventLogsEntryWithOwningAsset() throws {
        let category = try makeCategory()
        let asset = try store.createAsset(name: "Camry", categoryID: category.id)
        let event = try store.addEvent(title: "Oil change", date: Date(), toAssetID: asset.id)

        let entry = try XCTUnwrap(store.activityLog.last)
        XCTAssertEqual(entry.kind, .event)
        XCTAssertEqual(entry.recordID, event.id)
        XCTAssertEqual(entry.owningAssetID, asset.id)
    }

    func testAddTransactionLogsEntryWithOwningAsset() throws {
        let category = try makeCategory()
        let asset = try store.createAsset(name: "Camry", categoryID: category.id)
        let txn = try store.addTransaction(details: "Tires", amount: 480, date: Date(), kind: .expense, toAssetID: asset.id)

        let entry = try XCTUnwrap(store.activityLog.last)
        XCTAssertEqual(entry.kind, .transaction)
        XCTAssertEqual(entry.recordID, txn.id)
        XCTAssertEqual(entry.owningAssetID, asset.id)
    }

    func testFailedCreationLogsNothing() {
        XCTAssertThrowsError(try store.createAsset(name: "Orphan", categoryID: UUID()))
        XCTAssertThrowsError(try store.addEvent(title: "X", date: Date(), toAssetID: UUID()))
        XCTAssertThrowsError(try store.addTransaction(details: "X", amount: 1, date: Date(), kind: .expense, toAssetID: UUID()))
        XCTAssertTrue(store.activityLog.isEmpty)
    }

    func testEntriesAccumulateInCreationOrder() throws {
        let category = try makeCategory()
        let asset = try store.createAsset(name: "House", categoryID: category.id)
        let event = try store.addEvent(title: "Inspection", date: Date(), toAssetID: asset.id)
        let txn = try store.addTransaction(details: "Repair", amount: 99, date: Date(), kind: .expense, toAssetID: asset.id)
        let second = try store.createAsset(name: "Shed", categoryID: category.id)

        XCTAssertEqual(store.activityLog.map(\.recordID), [asset.id, event.id, txn.id, second.id])
        XCTAssertEqual(store.activityLog.map(\.kind), [.asset, .event, .transaction, .asset])
    }
}
