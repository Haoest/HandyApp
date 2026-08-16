import XCTest
@testable import HandyApp3

final class DuplicateSeriesTests: XCTestCase {

    var store: AssetStore!
    var asset: Asset!

    override func setUp() {
        super.setUp()
        store = AssetStore()
        let categoryID = try! store.createCategory(name: "Test").id
        asset = try! store.createAsset(name: "Asset", categoryID: categoryID)
    }

    // MARK: - Events

    func testFirstDuplicateOfRecurringEventAssignsSharedSeriesIDAndBumpsSourceModifyDate() throws {
        let source = try store.addEvent(title: "Rent", date: Date(), recurrence: .monthly, toAssetID: asset.id)
        XCTAssertNil(source.seriesID)
        let beforeModify = source.modifyDate

        let copy = try store.duplicateEvent(id: source.id, onAssetID: asset.id)

        XCTAssertNotNil(source.seriesID)
        XCTAssertEqual(copy.seriesID, source.seriesID)
        XCTAssertGreaterThan(source.modifyDate, beforeModify)
        XCTAssertEqual(copy.recurrence, .monthly, "series duplicates inherit recurrence")
        XCTAssertTrue(copy.title.hasPrefix("Rent"))
        XCTAssertNotEqual(copy.title, source.title)
    }

    func testSecondDuplicateReusesSeriesIDAndDoesNotTouchSource() throws {
        let source = try store.addEvent(title: "Rent", date: Date(), recurrence: .monthly, toAssetID: asset.id)
        let firstCopy = try store.duplicateEvent(id: source.id, onAssetID: asset.id)
        let seriesID = source.seriesID
        let sourceModifyAfterFirst = source.modifyDate

        let secondCopy = try store.duplicateEvent(id: firstCopy.id, onAssetID: asset.id)

        XCTAssertEqual(source.seriesID, seriesID)
        XCTAssertEqual(secondCopy.seriesID, seriesID)
        XCTAssertEqual(source.modifyDate, sourceModifyAfterFirst, "source untouched on later duplicates")
    }

    func testDuplicateOfNonRecurringEventStaysOutsideAnySeries() throws {
        let source = try store.addEvent(title: "One-off", date: Date(), toAssetID: asset.id)
        let copy = try store.duplicateEvent(id: source.id, onAssetID: asset.id)

        XCTAssertNil(source.seriesID)
        XCTAssertNil(copy.seriesID)
        XCTAssertNil(copy.recurrence)
        XCTAssertEqual(copy.title, "One-off", "non-recurring duplicates keep the title verbatim")
    }

    func testDuplicateAdvancesDueDateByOneRecurrenceInterval() throws {
        let calendar = Calendar(identifier: .gregorian)
        let due = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let source = try store.addEvent(title: "Rent", date: Date(), recurrence: .monthly,
                                        due: DueSettings(dueDate: due), toAssetID: asset.id)
        let copy = try store.duplicateEvent(id: source.id, onAssetID: asset.id)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        XCTAssertEqual(copy.dueDate, expected)
    }

    func testDuplicateEventThrowsAtCapacityLimit() throws {
        store.eventCreationLimit = 1
        let source = try store.addEvent(title: "Rent", date: Date(), recurrence: .monthly, toAssetID: asset.id)
        XCTAssertThrowsError(try store.duplicateEvent(id: source.id, onAssetID: asset.id)) { error in
            guard case AssetStoreError.freeEventLimitReached = error else { return XCTFail("Expected freeEventLimitReached") }
        }
    }

    func testExplicitDuplicateOverloadPersistsFormValuesAndAssignsSeries() throws {
        let source = try store.addEvent(title: "Rent", date: Date(), recurrence: .monthly, toAssetID: asset.id)
        let due = DueSettings(dueDate: Date(), messageDaysBefore: 14, messageDaysAfter: 1, deviceNotificationOn: true, deviceNotificationDaysBefore: 7)

        let copy = try store.duplicateEvent(id: source.id, onAssetID: asset.id, title: "Rent (custom)", date: Date(), notes: "custom notes", recurrence: .monthly, due: due)

        XCTAssertEqual(copy.title, "Rent (custom)")
        XCTAssertEqual(copy.notes, "custom notes")
        XCTAssertEqual(copy.messageDaysBefore, 14)
        XCTAssertEqual(copy.messageDaysAfter, 1)
        XCTAssertTrue(copy.deviceNotificationOn)
        XCTAssertEqual(copy.seriesID, source.seriesID)
        XCTAssertNotNil(copy.seriesID)
    }

    // MARK: - Transactions (mirror)

    func testFirstDuplicateOfRecurringTransactionAssignsSharedSeriesID() throws {
        let source = try store.addTransaction(details: "Insurance", amount: 100, date: Date(), kind: .expense, recurrence: .quarterly, toAssetID: asset.id)
        XCTAssertNil(source.seriesID)

        let copy = try store.duplicateTransaction(id: source.id, onAssetID: asset.id)

        XCTAssertNotNil(source.seriesID)
        XCTAssertEqual(copy.seriesID, source.seriesID)
        XCTAssertEqual(copy.recurrence, .quarterly)
        XCTAssertNotEqual(copy.details, source.details)
    }

    func testDuplicateTransactionThrowsAtCapacityLimit() throws {
        store.transactionCreationLimit = 1
        let source = try store.addTransaction(details: "Insurance", amount: 100, date: Date(), kind: .expense, recurrence: .quarterly, toAssetID: asset.id)
        XCTAssertThrowsError(try store.duplicateTransaction(id: source.id, onAssetID: asset.id)) { error in
            guard case AssetStoreError.freeTransactionLimitReached = error else { return XCTFail("Expected freeTransactionLimitReached") }
        }
    }
}
