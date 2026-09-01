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

    // Log Now dates the occurrence today and rolls the previous occurrence's due date forward
    // in whole intervals until it clears that date — so logging against a stale series lands on
    // the next grid date rather than one interval past today, and is never born overdue.
    // Asserted by property rather than by literal date: the store stamps the occurrence with
    // the real `Date()`, which no test can pin.
    func testLogNowRollsDueDateForwardToTheFirstGridDateAfterToday() throws {
        let calendar = Calendar.current
        let today = Date()
        let staleDue = calendar.date(byAdding: .month, value: -3, to: today)!
        let source = try store.addEvent(title: "Rent", date: today, recurrence: .monthly,
                                        due: DueSettings(dueDate: staleDue), toAssetID: asset.id)
        let copy = try store.duplicateEvent(id: source.id, onAssetID: asset.id)

        let projected = try XCTUnwrap(copy.dueDate)
        XCTAssertGreaterThan(calendar.startOfDay(for: projected), calendar.startOfDay(for: today),
                             "a freshly logged occurrence is never already overdue")
        let oneIntervalEarlier = calendar.date(byAdding: .month, value: -1, to: projected)!
        XCTAssertLessThanOrEqual(calendar.startOfDay(for: oneIntervalEarlier), calendar.startOfDay(for: today),
                                 "it is the first such date, not several intervals out")
    }

    func testLogNowDuplicateOfNonRecurringSourceTurnsDeviceNotificationOff() throws {
        // projectedDueDate copies a non-recurring source's due date verbatim, so inheriting the
        // toggle would schedule two identical reminders for the same moment (no seriesID is
        // assigned to silence either via isSuppressed).
        let source = try store.addEvent(title: "Warranty check", date: Date(),
                                        due: DueSettings(dueDate: Date(), deviceNotificationOn: true), toAssetID: asset.id)
        let copy = try store.duplicateEvent(id: source.id, onAssetID: asset.id)
        XCTAssertFalse(copy.deviceNotificationOn)
        XCTAssertTrue(source.deviceNotificationOn, "source's own notification is untouched")
    }

    func testLogNowDuplicateOfRecurringSourceKeepsDeviceNotificationOn() throws {
        let source = try store.addEvent(title: "Rent", date: Date(), recurrence: .monthly,
                                        due: DueSettings(dueDate: Date(), deviceNotificationOn: true), toAssetID: asset.id)
        let copy = try store.duplicateEvent(id: source.id, onAssetID: asset.id)
        XCTAssertTrue(copy.deviceNotificationOn)
    }

    func testDuplicateEventThrowsAtCapacityLimit() throws {
        store.recordCreationLimit = 1
        let source = try store.addEvent(title: "Rent", date: Date(), recurrence: .monthly, toAssetID: asset.id)
        XCTAssertThrowsError(try store.duplicateEvent(id: source.id, onAssetID: asset.id)) { error in
            guard case AssetStoreError.freeRecordLimitReached = error else { return XCTFail("Expected freeRecordLimitReached") }
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

    func testLogNowDuplicateOfNonRecurringTransactionTurnsDeviceNotificationOff() throws {
        let source = try store.addTransaction(details: "Warranty", amount: 50, date: Date(), kind: .expense,
                                              due: DueSettings(dueDate: Date(), deviceNotificationOn: true), toAssetID: asset.id)
        let copy = try store.duplicateTransaction(id: source.id, onAssetID: asset.id)
        XCTAssertFalse(copy.deviceNotificationOn)
    }

    func testDuplicateTransactionThrowsAtCapacityLimit() throws {
        store.recordCreationLimit = 1
        let source = try store.addTransaction(details: "Insurance", amount: 100, date: Date(), kind: .expense, recurrence: .quarterly, toAssetID: asset.id)
        XCTAssertThrowsError(try store.duplicateTransaction(id: source.id, onAssetID: asset.id)) { error in
            guard case AssetStoreError.freeRecordLimitReached = error else { return XCTFail("Expected freeRecordLimitReached") }
        }
    }
}
