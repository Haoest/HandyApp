import XCTest
@testable import HandyApp3

final class AttachmentStoreTests: XCTestCase {

    var store: AssetStore!
    var assetID: UUID!

    override func setUp() {
        super.setUp()
        store = AssetStore()
        let cat = try! store.createCategory(name: "Test")
        let asset = try! store.createAsset(name: "TestAsset", categoryID: cat.id)
        assetID = asset.id
    }

    // MARK: - Photo

    func testAddPhotoAppendsAndReturns() throws {
        let photo = try store.addPhoto(imageData: Data([1, 2, 3]), thumbnailData: Data([4, 5]), toAssetID: assetID)
        let asset = store.assets[assetID]!
        XCTAssertEqual(asset.photos.count, 1)
        XCTAssertEqual(asset.photos.first?.id, photo.id)
    }

    func testAddPhotoBumpsModifiedDate() throws {
        let before = store.assets[assetID]!.modifiedDate
        _ = try store.addPhoto(imageData: Data([1]), thumbnailData: Data([2]), toAssetID: assetID)
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testUpdatePhotoCaptionBumpsModifiedDate() throws {
        let photo = try store.addPhoto(imageData: Data([1]), thumbnailData: Data([2]), toAssetID: assetID)
        let before = store.assets[assetID]!.modifiedDate
        try store.updatePhotoCaption("New caption", forPhotoID: photo.id, onAssetID: assetID)
        XCTAssertEqual(store.assets[assetID]!.photos.first?.caption, "New caption")
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testRemovePhotoRoundTrip() throws {
        let photo = try store.addPhoto(imageData: Data([1]), thumbnailData: Data([2]), toAssetID: assetID)
        XCTAssertEqual(store.assets[assetID]!.photos.count, 1)
        let before = store.assets[assetID]!.modifiedDate
        try store.removePhoto(id: photo.id, fromAssetID: assetID)
        XCTAssertEqual(store.assets[assetID]!.photos.count, 0)
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testAddPhotoUnknownAssetThrows() {
        XCTAssertThrowsError(try store.addPhoto(imageData: Data(), thumbnailData: Data(), toAssetID: UUID())) { error in
            guard case AssetStoreError.assetNotFound = error else { return XCTFail("Expected assetNotFound") }
        }
    }

    func testRemovePhotoUnknownPhotoThrows() throws {
        XCTAssertThrowsError(try store.removePhoto(id: UUID(), fromAssetID: assetID)) { error in
            guard case AssetStoreError.photoNotFound = error else { return XCTFail("Expected photoNotFound") }
        }
    }

    // MARK: - Event

    func testAddEventAppendsAndReturns() throws {
        let event = try store.addEvent(title: "Repair", date: Date(), toAssetID: assetID)
        let asset = store.assets[assetID]!
        XCTAssertEqual(asset.events.count, 1)
        XCTAssertEqual(asset.events.first?.id, event.id)
    }

    func testAddEventBumpsModifiedDate() throws {
        let before = store.assets[assetID]!.modifiedDate
        _ = try store.addEvent(title: "Service", date: Date(), toAssetID: assetID)
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testUpdateEventBumpsModifiedDate() throws {
        let event = try store.addEvent(title: "Old", date: Date(), toAssetID: assetID)
        let before = store.assets[assetID]!.modifiedDate
        try store.updateEvent(id: event.id, onAssetID: assetID, title: "New", date: Date(), notes: "note", recurrence: nil)
        XCTAssertEqual(store.assets[assetID]!.events.first?.title, "New")
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testEventRecurrenceRoundTrip() throws {
        let event = try store.addEvent(title: "Service", date: Date(), notes: "", recurrence: .monthly, toAssetID: assetID)
        XCTAssertEqual(store.assets[assetID]!.events.first?.recurrence, .monthly)
        try store.updateEvent(id: event.id, onAssetID: assetID, title: "Service", date: Date(), notes: "", recurrence: .annually)
        XCTAssertEqual(store.assets[assetID]!.events.first?.recurrence, .annually)
        try store.updateEvent(id: event.id, onAssetID: assetID, title: "Service", date: Date(), notes: "", recurrence: nil)
        XCTAssertNil(store.assets[assetID]!.events.first?.recurrence)
    }

    func testRemoveEventRoundTrip() throws {
        let event = try store.addEvent(title: "X", date: Date(), toAssetID: assetID)
        let before = store.assets[assetID]!.modifiedDate
        try store.removeEvent(id: event.id, fromAssetID: assetID)
        XCTAssertEqual(store.assets[assetID]!.events.count, 0)
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testAddEventUnknownAssetThrows() {
        XCTAssertThrowsError(try store.addEvent(title: "X", date: Date(), toAssetID: UUID())) { error in
            guard case AssetStoreError.assetNotFound = error else { return XCTFail("Expected assetNotFound") }
        }
    }

    func testRemoveEventUnknownEventThrows() {
        XCTAssertThrowsError(try store.removeEvent(id: UUID(), fromAssetID: assetID)) { error in
            guard case AssetStoreError.eventNotFound = error else { return XCTFail("Expected eventNotFound") }
        }
    }

    // MARK: - Transaction

    func testAddTransactionAppendsAndReturns() throws {
        let txn = try store.addTransaction(details: "Oil change", amount: 50, date: Date(), kind: .expense, toAssetID: assetID)
        let asset = store.assets[assetID]!
        XCTAssertEqual(asset.transactions.count, 1)
        XCTAssertEqual(asset.transactions.first?.id, txn.id)
    }

    func testAddTransactionBumpsModifiedDate() throws {
        let before = store.assets[assetID]!.modifiedDate
        _ = try store.addTransaction(details: "X", amount: 1, date: Date(), kind: .income, toAssetID: assetID)
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testAddTransactionClampsNegativeAmount() throws {
        let txn = try store.addTransaction(details: "X", amount: -100, date: Date(), kind: .expense, toAssetID: assetID)
        XCTAssertEqual(txn.amount, 100)
    }

    func testUpdateTransactionBumpsModifiedDate() throws {
        let txn = try store.addTransaction(details: "Old", amount: 10, date: Date(), kind: .expense, toAssetID: assetID)
        let before = store.assets[assetID]!.modifiedDate
        try store.updateTransaction(id: txn.id, onAssetID: assetID, details: "New", amount: 20, date: Date(), kind: .income, payeeContactID: nil, notes: "", recurrence: nil)
        XCTAssertEqual(store.assets[assetID]!.transactions.first?.details, "New")
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testTransactionRecurrenceRoundTrip() throws {
        let txn = try store.addTransaction(details: "Pool", amount: 100, date: Date(), kind: .expense, recurrence: .quarterly, toAssetID: assetID)
        XCTAssertEqual(store.assets[assetID]!.transactions.first?.recurrence, .quarterly)
        try store.updateTransaction(id: txn.id, onAssetID: assetID, details: "Pool", amount: 100, date: Date(), kind: .expense, payeeContactID: nil, notes: "", recurrence: nil)
        XCTAssertNil(store.assets[assetID]!.transactions.first?.recurrence)
    }

    func testRemoveTransactionRoundTrip() throws {
        let txn = try store.addTransaction(details: "X", amount: 5, date: Date(), kind: .expense, toAssetID: assetID)
        let before = store.assets[assetID]!.modifiedDate
        try store.removeTransaction(id: txn.id, fromAssetID: assetID)
        XCTAssertEqual(store.assets[assetID]!.transactions.count, 0)
        XCTAssertGreaterThan(store.assets[assetID]!.modifiedDate, before)
    }

    func testAddTransactionUnknownAssetThrows() {
        XCTAssertThrowsError(try store.addTransaction(details: "X", amount: 1, date: Date(), kind: .expense, toAssetID: UUID())) { error in
            guard case AssetStoreError.assetNotFound = error else { return XCTFail("Expected assetNotFound") }
        }
    }

    func testRemoveTransactionUnknownTransactionThrows() {
        XCTAssertThrowsError(try store.removeTransaction(id: UUID(), fromAssetID: assetID)) { error in
            guard case AssetStoreError.transactionNotFound = error else { return XCTFail("Expected transactionNotFound") }
        }
    }
}
