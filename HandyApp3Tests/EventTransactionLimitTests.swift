import XCTest
@testable import HandyApp3

/// Events and transactions draw on one shared per-asset allowance (`recordCreationLimit`),
/// so these cover both kinds individually *and* the mixing between them.
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

    // MARK: - No limit set

    func testNoLimitByDefault() throws {
        for i in 0..<6 {
            try makeEvent(on: assetA, title: "Event \(i)")
            try makeTransaction(on: assetA, details: "Txn \(i)")
        }
        XCTAssertEqual(assetA.liveRecordCount, 12)
        XCTAssertTrue(store.hasRecordCapacity(for: assetA))
    }

    // MARK: - Each kind against the shared limit

    func testSixthEventThrowsAtLimitFive() throws {
        store.recordCreationLimit = 5
        for i in 0..<5 {
            try makeEvent(on: assetA, title: "Event \(i)")
        }
        XCTAssertThrowsError(try makeEvent(on: assetA, title: "Sixth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeRecordLimitReached(limit: 5))
        }
    }

    func testSixthTransactionThrowsAtLimitFive() throws {
        store.recordCreationLimit = 5
        for i in 0..<5 {
            try makeTransaction(on: assetA, details: "Txn \(i)")
        }
        XCTAssertThrowsError(try makeTransaction(on: assetA, details: "Sixth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeRecordLimitReached(limit: 5))
        }
    }

    // MARK: - The two kinds share one allowance

    func testEventsAndTransactionsCountTowardTheSameLimit() throws {
        store.recordCreationLimit = 5
        for i in 0..<3 { try makeEvent(on: assetA, title: "Event \(i)") }
        for i in 0..<2 { try makeTransaction(on: assetA, details: "Txn \(i)") }
        XCTAssertEqual(assetA.liveRecordCount, 5)
        XCTAssertFalse(store.hasRecordCapacity(for: assetA))
        XCTAssertThrowsError(try makeEvent(on: assetA, title: "Sixth"))
        XCTAssertThrowsError(try makeTransaction(on: assetA, details: "Sixth"))
    }

    /// The tightest reading of "shared": events alone can exhaust the allowance a
    /// transaction would otherwise have used.
    func testEventsAloneCanExhaustTheTransactionAllowance() throws {
        store.recordCreationLimit = 5
        for i in 0..<5 { try makeEvent(on: assetA, title: "Event \(i)") }
        XCTAssertEqual(assetA.liveTransactions.count, 0)
        XCTAssertThrowsError(try makeTransaction(on: assetA)) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeRecordLimitReached(limit: 5))
        }
    }

    func testTransactionsAloneCanExhaustTheEventAllowance() throws {
        store.recordCreationLimit = 5
        for i in 0..<5 { try makeTransaction(on: assetA, details: "Txn \(i)") }
        XCTAssertEqual(assetA.liveEvents.count, 0)
        XCTAssertThrowsError(try makeEvent(on: assetA)) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeRecordLimitReached(limit: 5))
        }
    }

    /// Deleting one kind frees a slot the other kind can take.
    func testRemovingAnEventFreesASlotForATransaction() throws {
        store.recordCreationLimit = 5
        var events: [Event] = []
        for i in 0..<5 { events.append(try makeEvent(on: assetA, title: "Event \(i)")) }
        XCTAssertThrowsError(try makeTransaction(on: assetA))
        try store.removeEvent(id: events[0].id, fromAssetID: assetA.id)
        XCTAssertNoThrow(try makeTransaction(on: assetA))
        XCTAssertEqual(assetA.liveRecordCount, 5)
    }

    // MARK: - Scope and state

    func testLimitIsPerAssetNotGlobal() throws {
        store.recordCreationLimit = 5
        for i in 0..<3 { try makeEvent(on: assetA, title: "Event \(i)") }
        for i in 0..<2 { try makeTransaction(on: assetA, details: "Txn \(i)") }
        XCTAssertThrowsError(try makeEvent(on: assetA))
        XCTAssertNoThrow(try makeEvent(on: assetB))
        XCTAssertNoThrow(try makeTransaction(on: assetB))
        XCTAssertEqual(assetB.liveRecordCount, 2)
    }

    func testHasRecordCapacityTracksState() throws {
        store.recordCreationLimit = 5
        for i in 0..<2 { try makeEvent(on: assetA, title: "Event \(i)") }
        for i in 0..<2 { try makeTransaction(on: assetA, details: "Txn \(i)") }
        XCTAssertTrue(store.hasRecordCapacity(for: assetA))
        try makeEvent(on: assetA, title: "Fifth")
        XCTAssertFalse(store.hasRecordCapacity(for: assetA))
        store.recordCreationLimit = nil
        XCTAssertTrue(store.hasRecordCapacity(for: assetA))
    }

    // MARK: - Tombstones

    func testTombstonedRecordsDoNotOccupyASlot() throws {
        store.recordCreationLimit = 5
        var events: [Event] = []
        var txns: [Transaction] = []
        for i in 0..<3 { events.append(try makeEvent(on: assetA, title: "Event \(i)")) }
        for i in 0..<2 { txns.append(try makeTransaction(on: assetA, details: "Txn \(i)")) }
        XCTAssertFalse(store.hasRecordCapacity(for: assetA))

        try store.removeEvent(id: events[0].id, fromAssetID: assetA.id)
        try store.removeTransaction(id: txns[0].id, fromAssetID: assetA.id)
        // The tombstones stay in the arrays until purge, but must not hold paywall slots.
        XCTAssertEqual(assetA.events.count, 3)
        XCTAssertEqual(assetA.transactions.count, 2)
        XCTAssertEqual(assetA.liveRecordCount, 3)
        XCTAssertTrue(store.hasRecordCapacity(for: assetA))
        XCTAssertNoThrow(try makeEvent(on: assetA, title: "Replacement"))
        XCTAssertNoThrow(try makeTransaction(on: assetA, details: "Replacement"))
    }

    // MARK: - Pre-existing overflow

    func testImportedOverflowStaysIntactButBlocksNewAdds() throws {
        // Simulates a JSON import (or a lapsed full version) that bypassed the limit: 8
        // records land on the asset before recordCreationLimit is ever set.
        for i in 0..<4 { try makeEvent(on: assetA, title: "Imported event \(i)") }
        for i in 0..<4 { try makeTransaction(on: assetA, details: "Imported txn \(i)") }
        XCTAssertEqual(assetA.liveRecordCount, 8)

        store.recordCreationLimit = 5
        // Setting the limit never truncates existing data.
        XCTAssertEqual(assetA.liveRecordCount, 8)

        XCTAssertThrowsError(try makeEvent(on: assetA, title: "Ninth")) { error in
            XCTAssertEqual(error as? AssetStoreError, .freeRecordLimitReached(limit: 5))
        }
        XCTAssertThrowsError(try makeTransaction(on: assetA, details: "Ninth"))

        // Pre-existing overflow items remain fully editable/removable.
        let event = assetA.events[0]
        XCTAssertNoThrow(try store.updateEvent(id: event.id, onAssetID: assetA.id, title: "Renamed", date: event.date, notes: "", recurrence: nil, due: DueSettings()))
        XCTAssertNoThrow(try store.removeEvent(id: event.id, fromAssetID: assetA.id))

        let txn = assetA.transactions[0]
        XCTAssertNoThrow(try store.updateTransaction(id: txn.id, onAssetID: assetA.id, details: "Renamed", amount: txn.amount, date: txn.date, kind: txn.kind, payeeContactID: nil, notes: "", recurrence: nil, due: DueSettings()))
        XCTAssertNoThrow(try store.removeTransaction(id: txn.id, fromAssetID: assetA.id))

        XCTAssertEqual(assetA.events.count, 4, "the tombstone stays until purge")
        XCTAssertEqual(assetA.transactions.count, 4, "the tombstone stays until purge")
        XCTAssertEqual(assetA.liveRecordCount, 6, "still over the limit, so still blocked")
        XCTAssertFalse(store.hasRecordCapacity(for: assetA))
    }
}
