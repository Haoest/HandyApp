import XCTest
@testable import HandyApp3

final class EventTransactionLimitTests: XCTestCase {

    var store: AssetStore!
    var assetA: Asset!
    var assetB: Asset!

    override func setUp() {
        super.setUp()
        store = AssetStore()
        let categoryID = try! store.createCategory(name: "Test").id
        assetA = try! store.createAsset(name: "Asset A", categoryID: categoryID)
        assetB = try! store.createAsset(name: "Asset B", categoryID: categoryID)
    }

    @discardableResult
    private func makeEvent(on asset: Asset, title: String = "Event") throws -> Event {
        try store.addEvent(title: title, date: Date(), toAssetID: asset.id)
    }

    @discardableResult
    private func makeTransaction(on asset: Asset, details: String = "Txn") throws -> Transaction {
        try store.addTransaction(details: details, amount: 10, date: Date(), kind: .expense, toAssetID: asset.id)
    }

    // MARK: - Events

    func testNoEventLimitByDefault() throws {
        for i in 0..<6 {
            try makeEvent(on: assetA, title: "Event \(i)")
        }
        XCTAssertEqual(assetA.events.count, 6)
    }

    func testSixthEventThrowsAtLimitFive() throws {
        store.eventCreationLimit = 5
        for i in 0..<5 {
            try makeEvent(on: assetA, title: "Event \(i)")
        }
        XCTAssertThrowsError(try makeEvent(on: assetA, title: "Sixth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeEventLimitReached(limit: 5))
        }
    }

    func testEventLimitIsPerAssetNotGlobal() throws {
        store.eventCreationLimit = 5
        for i in 0..<5 {
            try makeEvent(on: assetA, title: "Event \(i)")
        }
        XCTAssertThrowsError(try makeEvent(on: assetA))
        XCTAssertNoThrow(try makeEvent(on: assetB))
        XCTAssertEqual(assetB.events.count, 1)
    }

    func testHasEventCapacityTracksState() throws {
        store.eventCreationLimit = 5
        for i in 0..<4 {
            try makeEvent(on: assetA, title: "Event \(i)")
        }
        XCTAssertTrue(store.hasEventCapacity(for: assetA))
        try makeEvent(on: assetA, title: "Fifth")
        XCTAssertFalse(store.hasEventCapacity(for: assetA))
        store.eventCreationLimit = nil
        XCTAssertTrue(store.hasEventCapacity(for: assetA))
    }

    func testRemovingEventFreesSlotUnderLimit() throws {
        store.eventCreationLimit = 5
        var created: [Event] = []
        for i in 0..<5 {
            created.append(try makeEvent(on: assetA, title: "Event \(i)"))
        }
        try store.removeEvent(id: created[0].id, fromAssetID: assetA.id)
        XCTAssertNoThrow(try makeEvent(on: assetA, title: "Replacement"))
    }

    func testImportedOverflowEventsStayIntactButBlockNewAdds() throws {
        // Simulates a JSON import that bypassed the limit: 8 events land on the
        // asset before eventCreationLimit is ever set.
        for i in 0..<8 {
            try makeEvent(on: assetA, title: "Imported \(i)")
        }
        XCTAssertEqual(assetA.events.count, 8)

        store.eventCreationLimit = 5
        // Setting the limit never truncates existing data.
        XCTAssertEqual(assetA.events.count, 8)

        XCTAssertThrowsError(try makeEvent(on: assetA, title: "Ninth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeEventLimitReached(limit: 5))
        }
        // Pre-existing overflow items remain fully editable/removable.
        let first = assetA.events[0]
        XCTAssertNoThrow(try store.updateEvent(id: first.id, onAssetID: assetA.id, title: "Renamed", date: first.date, notes: "", recurrence: nil))
        XCTAssertNoThrow(try store.removeEvent(id: first.id, fromAssetID: assetA.id))
        XCTAssertEqual(assetA.events.count, 7)
    }

    // MARK: - Transactions

    func testNoTransactionLimitByDefault() throws {
        for i in 0..<6 {
            try makeTransaction(on: assetA, details: "Txn \(i)")
        }
        XCTAssertEqual(assetA.transactions.count, 6)
    }

    func testSixthTransactionThrowsAtLimitFive() throws {
        store.transactionCreationLimit = 5
        for i in 0..<5 {
            try makeTransaction(on: assetA, details: "Txn \(i)")
        }
        XCTAssertThrowsError(try makeTransaction(on: assetA, details: "Sixth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeTransactionLimitReached(limit: 5))
        }
    }

    func testTransactionLimitIsPerAssetNotGlobal() throws {
        store.transactionCreationLimit = 5
        for i in 0..<5 {
            try makeTransaction(on: assetA, details: "Txn \(i)")
        }
        XCTAssertThrowsError(try makeTransaction(on: assetA))
        XCTAssertNoThrow(try makeTransaction(on: assetB))
        XCTAssertEqual(assetB.transactions.count, 1)
    }

    func testHasTransactionCapacityTracksState() throws {
        store.transactionCreationLimit = 5
        for i in 0..<4 {
            try makeTransaction(on: assetA, details: "Txn \(i)")
        }
        XCTAssertTrue(store.hasTransactionCapacity(for: assetA))
        try makeTransaction(on: assetA, details: "Fifth")
        XCTAssertFalse(store.hasTransactionCapacity(for: assetA))
        store.transactionCreationLimit = nil
        XCTAssertTrue(store.hasTransactionCapacity(for: assetA))
    }

    func testRemovingTransactionFreesSlotUnderLimit() throws {
        store.transactionCreationLimit = 5
        var created: [Transaction] = []
        for i in 0..<5 {
            created.append(try makeTransaction(on: assetA, details: "Txn \(i)"))
        }
        try store.removeTransaction(id: created[0].id, fromAssetID: assetA.id)
        XCTAssertNoThrow(try makeTransaction(on: assetA, details: "Replacement"))
    }

    func testImportedOverflowTransactionsStayIntactButBlockNewAdds() throws {
        for i in 0..<8 {
            try makeTransaction(on: assetA, details: "Imported \(i)")
        }
        XCTAssertEqual(assetA.transactions.count, 8)

        store.transactionCreationLimit = 5
        XCTAssertEqual(assetA.transactions.count, 8)

        XCTAssertThrowsError(try makeTransaction(on: assetA, details: "Ninth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeTransactionLimitReached(limit: 5))
        }
        let first = assetA.transactions[0]
        XCTAssertNoThrow(try store.updateTransaction(id: first.id, onAssetID: assetA.id, details: "Renamed", amount: first.amount, date: first.date, kind: first.kind, payeeContactID: nil, notes: "", recurrence: nil))
        XCTAssertNoThrow(try store.removeTransaction(id: first.id, fromAssetID: assetA.id))
        XCTAssertEqual(assetA.transactions.count, 7)
    }
}
