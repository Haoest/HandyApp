import XCTest
@testable import HandyApp3

final class NotificationPlannerTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private var store: AssetStore!
    private var assetID: UUID!

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    override func setUp() {
        super.setUp()
        store = AssetStore()
        let cat = try! store.createCategory(name: "Test")
        let asset = try! store.createAsset(name: "My House", categoryID: cat.id)
        assetID = asset.id
    }

    func testNonRecurringRecordsProduceNoPlan() throws {
        _ = try store.addEvent(title: "One-off", date: date(2026, 1, 1), toAssetID: assetID)
        _ = try store.addTransaction(details: "One-off", amount: 5, date: date(2026, 1, 1), kind: .expense, toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func testRecurringRecordWithToggleOffAndNoDueDateProducesNoPlan() throws {
        // Recurrence alone no longer drives scheduling — only the due-date/toggle formula does.
        _ = try store.addEvent(title: "Furnace service", date: date(2026, 1, 10), recurrence: .monthly, toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 15), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Due-date device notifications

    func testEventDueNotificationIdentifierFireTimeAndKind() throws {
        let due = date(2026, 2, 1)
        let event = try store.addEvent(title: "Inspection", date: date(2026, 1, 1),
                                       due: DueSettings(dueDate: due, deviceNotificationOn: true, deviceNotificationDaysBefore: 7),
                                       toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        let planned = plan.first { $0.identifier == "due-event-\(event.id.uuidString)" }
        XCTAssertNotNil(planned)
        XCTAssertEqual(planned?.fireDate, date(2026, 1, 25, hour: 9))
        XCTAssertEqual(planned?.title, "My House")
        XCTAssertEqual(planned?.body, "Due in 7 days: Inspection.")
        XCTAssertEqual(planned?.assetID, assetID)
        XCTAssertEqual(planned?.kind, .event)
    }

    func testEventDueNotificationBodyAppendsNotesWhenPresent() throws {
        let event = try store.addEvent(title: "Inspection", date: date(2026, 1, 1), notes: "Bring the ladder",
                                       due: DueSettings(dueDate: date(2026, 2, 1), deviceNotificationOn: true, deviceNotificationDaysBefore: 7),
                                       toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        let planned = plan.first { $0.identifier == "due-event-\(event.id.uuidString)" }
        XCTAssertEqual(planned?.body, "Due in 7 days: Inspection. Bring the ladder")
    }

    func testTransactionDueNotificationIdentifierBodyAndKind() throws {
        let due = date(2026, 2, 1)
        let txn = try store.addTransaction(details: "Pool service", amount: 100, date: date(2026, 1, 1), kind: .expense,
                                           due: DueSettings(dueDate: due, deviceNotificationOn: true, deviceNotificationDaysBefore: 7),
                                           toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        let planned = plan.first { $0.identifier == "due-txn-\(txn.id.uuidString)" }
        XCTAssertNotNil(planned)
        XCTAssertEqual(planned?.fireDate, date(2026, 1, 25, hour: 9))
        let body = planned?.body ?? ""
        XCTAssertTrue(body.contains("Expense transaction due in 7 days in amount of"))
        XCTAssertTrue(body.contains("100"))
        XCTAssertEqual(planned?.kind, .transaction)
    }

    func testNoDueNotificationWhenDeviceNotificationOff() throws {
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1), due: DueSettings(dueDate: date(2026, 2, 1)), toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.allSatisfy { !$0.identifier.hasPrefix("due-") })
    }

    func testNoDueNotificationWhenNoDueDate() throws {
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1), due: DueSettings(deviceNotificationOn: true), toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.allSatisfy { !$0.identifier.hasPrefix("due-") })
    }

    func testElapsedTriggerProducesNoNotification() throws {
        // Trigger moment (due - daysBefore) is entirely in the past — not just its 9 AM.
        let due = date(2026, 1, 10, hour: 8)
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1),
                               due: DueSettings(dueDate: due, deviceNotificationOn: true, deviceNotificationDaysBefore: 0),
                               toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 10, hour: 9), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func testSuppressedRecordProducesNoDueNotification() throws {
        let source = try store.addEvent(title: "Rent", date: date(2026, 1, 1), recurrence: .monthly,
                                        due: DueSettings(dueDate: date(2026, 2, 1), deviceNotificationOn: true),
                                        toAssetID: assetID)
        // A newer occurrence for the current period suppresses the older source's due reminder.
        _ = try store.duplicateEvent(id: source.id, onAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertFalse(plan.contains { $0.identifier == "due-event-\(source.id.uuidString)" })
    }

    func testRecurringDuplicateStillSchedulesDueNotificationForNewestMember() throws {
        let source = try store.addEvent(title: "Rent", date: date(2026, 1, 1), recurrence: .monthly,
                                        due: DueSettings(dueDate: date(2026, 2, 1), deviceNotificationOn: true),
                                        toAssetID: assetID)
        let copy = try store.duplicateEvent(id: source.id, onAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.contains { $0.identifier == "due-event-\(copy.id.uuidString)" })
    }

    func testDuplicateOfNonRecurringSourceDoesNotDoubleScheduleDueNotification() throws {
        // Source's due date is copied verbatim (projectedDueDate only rolls a recurring
        // source), and no seriesID is assigned, so without the guard in
        // duplicateEvent(id:onAssetID:) both records would schedule identical reminders.
        let source = try store.addEvent(title: "Warranty check", date: date(2026, 1, 1),
                                        due: DueSettings(dueDate: date(2026, 2, 1), deviceNotificationOn: true, deviceNotificationDaysBefore: 7),
                                        toAssetID: assetID)
        let copy = try store.duplicateEvent(id: source.id, onAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.contains { $0.identifier == "due-event-\(source.id.uuidString)" })
        XCTAssertFalse(plan.contains { $0.identifier == "due-event-\(copy.id.uuidString)" })
    }

    // MARK: - Soft delete

    func testSoftDeletedAssetExcludedViaAllAssets() throws {
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1), due: DueSettings(dueDate: date(2026, 2, 1), deviceNotificationOn: true), toAssetID: assetID)
        try store.softDeleteAsset(id: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func testSoftDeletedEventExcludedFromPlan() throws {
        let event = try store.addEvent(title: "X", date: date(2026, 1, 1), due: DueSettings(dueDate: date(2026, 2, 1), deviceNotificationOn: true), toAssetID: assetID)
        try store.removeEvent(id: event.id, fromAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func testSoftDeletedTransactionExcludedFromPlan() throws {
        let txn = try store.addTransaction(details: "X", amount: 5, date: date(2026, 1, 1), kind: .expense,
                                           due: DueSettings(dueDate: date(2026, 2, 1), deviceNotificationOn: true), toAssetID: assetID)
        try store.removeTransaction(id: txn.id, fromAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Same-day fallback (fires at the exact trigger moment, not just 9 AM)

    func testSameDayFallbackSchedulesAtExactTriggerWhenNineAMHasPassed() throws {
        // Trigger moment is today at 15:00 (due date's own time of day, 0 days lead).
        let due = date(2026, 1, 10, hour: 15)
        let event = try store.addEvent(title: "X", date: date(2026, 1, 1),
                                       due: DueSettings(dueDate: due, deviceNotificationOn: true, deviceNotificationDaysBefore: 0),
                                       toAssetID: assetID)
        // 9 AM has passed, but the exact trigger moment (15:00) has not.
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 10, hour: 12), calendar: calendar)
        let planned = plan.first { $0.identifier == "due-event-\(event.id.uuidString)" }
        XCTAssertEqual(planned?.fireDate, due)
        XCTAssertEqual(planned?.fireDateComponents.hour, 15)
        XCTAssertEqual(planned?.fireDateComponents.minute, 0)
    }

    func testSameDayFallbackDropsWhenTriggerMomentHasAlsoPassed() throws {
        let due = date(2026, 1, 10, hour: 15)
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1),
                               due: DueSettings(dueDate: due, deviceNotificationOn: true, deviceNotificationDaysBefore: 0),
                               toAssetID: assetID)
        // Both 9 AM and the exact trigger moment (15:00) have passed.
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 10, hour: 16), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func testFutureDayStillFiresAtNineAM() throws {
        // Confirms the fallback only ever engages on the trigger's own day — a future day
        // schedules at 9 AM regardless of the due date's time-of-day.
        let due = date(2026, 1, 12, hour: 15)
        let event = try store.addEvent(title: "X", date: date(2026, 1, 1),
                                       due: DueSettings(dueDate: due, deviceNotificationOn: true, deviceNotificationDaysBefore: 0),
                                       toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 10, hour: 16), calendar: calendar)
        let planned = plan.first { $0.identifier == "due-event-\(event.id.uuidString)" }
        XCTAssertEqual(planned?.fireDate, date(2026, 1, 12, hour: 9))
    }

    // MARK: - Global cap

    func testGlobalCapKeepsSoonestDueNotifications() throws {
        let catB = try store.createCategory(name: "Other")
        let assetB = try store.createAsset(name: "My Car", categoryID: catB.id)
        for (i, day) in [1, 2, 3, 4].enumerated() {
            _ = try store.addEvent(title: "A\(i)", date: date(2026, 1, 1),
                                   due: DueSettings(dueDate: date(2026, 1, day + 10), deviceNotificationOn: true, deviceNotificationDaysBefore: 0),
                                   toAssetID: assetID)
        }
        for (i, day) in [5, 6, 7, 8].enumerated() {
            _ = try store.addTransaction(details: "B\(i)", amount: 1, date: date(2026, 1, 1), kind: .expense,
                                         due: DueSettings(dueDate: date(2026, 1, day + 10), deviceNotificationOn: true, deviceNotificationDaysBefore: 0),
                                         toAssetID: assetB.id)
        }
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar, globalLimit: 3)
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(plan.map(\.fireDate), [date(2026, 1, 11, hour: 9), date(2026, 1, 12, hour: 9), date(2026, 1, 13, hour: 9)])
    }
}
