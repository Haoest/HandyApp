import XCTest
@testable import HandyApp3

final class RecurrenceIntervalTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testWeeklyAddsSevenDays() {
        let base = date(2026, 1, 1)
        let occ = RecurrenceInterval.weekly.occurrences(from: base, after: base, count: 2, calendar: calendar)
        XCTAssertEqual(occ.map(\.date), [date(2026, 1, 8), date(2026, 1, 15)])
        XCTAssertEqual(occ.map(\.index), [1, 2])
    }

    func testMonthlyFromJan31DoesNotDriftAfterClamp() {
        let base = date(2026, 1, 31)
        let occ = RecurrenceInterval.monthly.occurrences(from: base, after: base, count: 3, calendar: calendar)
        XCTAssertEqual(occ.map(\.date), [date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)])
    }

    func testQuarterlyAndSemiAnnually() {
        let base = date(2026, 1, 15)
        XCTAssertEqual(RecurrenceInterval.quarterly.occurrences(from: base, after: base, count: 1, calendar: calendar).map(\.date), [date(2026, 4, 15)])
        XCTAssertEqual(RecurrenceInterval.semiAnnually.occurrences(from: base, after: base, count: 1, calendar: calendar).map(\.date), [date(2026, 7, 15)])
    }

    func testAnnuallyFromLeapDayClampsToFeb28() {
        let base = date(2024, 2, 29)
        let occ = RecurrenceInterval.annually.occurrences(from: base, after: base, count: 1, calendar: calendar)
        XCTAssertEqual(occ.map(\.date), [date(2025, 2, 28)])
    }

    func testBiAnnuallyAddsTwoYears() {
        let base = date(2026, 3, 15)
        let occ = RecurrenceInterval.biAnnually.occurrences(from: base, after: base, count: 2, calendar: calendar)
        XCTAssertEqual(occ.map(\.date), [date(2028, 3, 15), date(2030, 3, 15)])
    }

    func testFutureBaseIncludesIndexZero() {
        let now = date(2026, 1, 1)
        let base = date(2026, 6, 1)
        let occ = RecurrenceInterval.monthly.occurrences(from: base, after: now, count: 2, calendar: calendar)
        XCTAssertEqual(occ.first?.index, 0)
        XCTAssertEqual(occ.first?.date, base)
    }

    func testOccurrencesAreStrictlyAfterReference() {
        let base = date(2026, 1, 1)
        let reference = date(2026, 3, 1)
        let occ = RecurrenceInterval.monthly.occurrences(from: base, after: reference, count: 1, calendar: calendar)
        XCTAssertEqual(occ.map(\.date), [date(2026, 4, 1)])
        XCTAssertEqual(occ.map(\.index), [3])
    }

    func testCountHonored() {
        let base = date(2026, 1, 1)
        let occ = RecurrenceInterval.weekly.occurrences(from: base, after: base, count: 12, calendar: calendar)
        XCTAssertEqual(occ.count, 12)
    }
}

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

    func testEventPlanIdentifierContentAndFireTime() throws {
        let event = try store.addEvent(title: "Furnace service", date: date(2026, 1, 10), notes: "", recurrence: .monthly, toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 15), calendar: calendar)
        XCTAssertEqual(plan.count, 12)
        let first = plan[0]
        XCTAssertEqual(first.identifier, "recurring-event-\(event.id.uuidString)-1")
        XCTAssertEqual(first.fireDateComponents.hour, 9)
        XCTAssertEqual(first.fireDateComponents.minute, 0)
        XCTAssertEqual(first.fireDate, date(2026, 2, 10, hour: 9))
        XCTAssertEqual(first.title, "My House")
        XCTAssertEqual(first.body, "Furnace service")
        XCTAssertEqual(first.assetID, assetID)
    }

    func testTransactionBodyContainsDetailsAmountAndKind() throws {
        let txn = try store.addTransaction(details: "Pool service", amount: 100, date: date(2026, 1, 10), kind: .expense, recurrence: .quarterly, toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 15), calendar: calendar)
        XCTAssertEqual(plan.first?.identifier, "recurring-txn-\(txn.id.uuidString)-1")
        let body = plan.first?.body ?? ""
        XCTAssertTrue(body.contains("Pool service"))
        XCTAssertTrue(body.contains("100"))
        XCTAssertTrue(body.contains("(Expense)"))
    }

    func testSameDayOccurrenceBeforeNineAMIsScheduled() throws {
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1), recurrence: .weekly, toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 8, hour: 7), calendar: calendar, perItemLimit: 1)
        XCTAssertEqual(plan.first?.fireDate, date(2026, 1, 8, hour: 9))
    }

    func testSameDayOccurrenceAfterNineAMIsDropped() throws {
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1), recurrence: .weekly, toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 8, hour: 10), calendar: calendar, perItemLimit: 2)
        XCTAssertEqual(plan.map(\.fireDate), [date(2026, 1, 15, hour: 9)])
    }

    func testGlobalCapKeepsSoonest() throws {
        _ = try store.addEvent(title: "A", date: date(2026, 1, 1), recurrence: .weekly, toAssetID: assetID)
        _ = try store.addEvent(title: "B", date: date(2026, 1, 2), recurrence: .weekly, toAssetID: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar, perItemLimit: 12, globalLimit: 5)
        // B's base date (Jan 2) is "today" at plan time, so it fires today at 9.
        // Soonest five: Jan 2 (B), 8 (A), 9 (B), 15 (A), 16 (B).
        XCTAssertEqual(plan.count, 5)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(plan.last?.fireDate, date(2026, 1, 16, hour: 9))
    }

    func testSoftDeletedAssetExcludedViaAllAssets() throws {
        _ = try store.addEvent(title: "X", date: date(2026, 1, 1), recurrence: .monthly, toAssetID: assetID)
        try store.softDeleteAsset(id: assetID)
        let plan = NotificationPlanner.plan(for: store.allAssets, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }
}
