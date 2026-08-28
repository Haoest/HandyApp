import XCTest
@testable import HandyApp3

final class ThingLogDigestTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private var now: Date { date(2026, 8, 15) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(_ title: String, on day: Date, due: Date? = nil,
                       recurrence: RecurrenceInterval? = nil, seriesID: UUID? = nil,
                       createdAt: TimeInterval = 0,
                       messageDaysAfter: Int = DueDefaults.messageDaysAfter) -> Event {
        Event(title: title, date: day, recurrence: recurrence, dueDate: due, seriesID: seriesID,
              createdAt: Date(timeIntervalSince1970: createdAt), messageDaysAfter: messageDaysAfter)
    }

    private func transaction(_ details: String, amount: Decimal, kind: TransactionKind,
                             on day: Date, due: Date? = nil,
                             recurrence: RecurrenceInterval? = nil, seriesID: UUID? = nil,
                             createdAt: TimeInterval = 0) -> Transaction {
        Transaction(details: details, amount: amount, date: day, kind: kind, recurrence: recurrence,
                    dueDate: due, seriesID: seriesID, createdAt: Date(timeIntervalSince1970: createdAt))
    }

    private func rows(events: [Event] = [], transactions: [Transaction] = []) -> [ThingLogRow] {
        ThingLogDigest.rows(events: events, transactions: transactions, calendar: calendar, now: now)
    }

    // MARK: - Shape

    func testEventsAndTransactionsBothBecomeRows() {
        let result = rows(events: [event("Oil change", on: date(2026, 8, 1))],
                          transactions: [transaction("Rent", amount: 1200, kind: .income, on: date(2026, 8, 2))])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.title)), ["Oil change", "Rent"])
    }

    func testExpenseIsNegativeAndIncomeIsPositive() {
        let result = rows(transactions: [
            transaction("Repair", amount: 300, kind: .expense, on: date(2026, 8, 1)),
            transaction("Rent", amount: 1200, kind: .income, on: date(2026, 8, 2)),
        ])
        XCTAssertEqual(result.first { $0.title == "Repair" }?.signedAmount, -300)
        XCTAssertEqual(result.first { $0.title == "Rent" }?.signedAmount, 1200)
    }

    func testEventRowsCarryNoAmount() {
        XCTAssertNil(rows(events: [event("Inspection", on: date(2026, 8, 1))]).first?.signedAmount)
    }

    // MARK: - Series collapsing

    func testSeriesCollapsesToOneRowRepresentedByTheNewestMember() {
        let series = UUID()
        let result = rows(events: [
            event("Oil change", on: date(2026, 6, 1), recurrence: .monthly, seriesID: series, createdAt: 100),
            event("Oil change", on: date(2026, 7, 1), recurrence: .monthly, seriesID: series, createdAt: 200),
            event("Oil change", on: date(2026, 8, 1), recurrence: .monthly, seriesID: series, createdAt: 300),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.date, date(2026, 8, 1))
        XCTAssertEqual(result.first?.seriesCount, 3)
    }

    /// The Timeline hides a series whose current occurrence is already logged; the Log tab
    /// is a record of what exists, so it must not.
    func testAlreadyLoggedSeriesStillAppears() {
        let series = UUID()
        let result = rows(events: [
            event("Oil change", on: date(2026, 8, 1), due: date(2026, 8, 10), recurrence: .monthly, seriesID: series, createdAt: 100),
            event("Oil change", on: date(2026, 8, 12), due: date(2026, 9, 12), recurrence: .monthly, seriesID: series, createdAt: 200),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.dueDate, date(2026, 9, 12))
    }

    func testTwoDistinctSeriesStayTwoRows() {
        let result = rows(events: [
            event("Oil change", on: date(2026, 8, 1), recurrence: .monthly, seriesID: UUID()),
            event("Tire rotation", on: date(2026, 8, 2), recurrence: .monthly, seriesID: UUID()),
        ])
        XCTAssertEqual(result.count, 2)
    }

    func testOneOffsAreNeverCollapsedTogether() {
        let result = rows(events: [
            event("Wash", on: date(2026, 8, 1)),
            event("Wash", on: date(2026, 8, 2)),
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.seriesCount == 1 })
    }

    // MARK: - Late

    func testPastDueRecordIsLate() {
        let result = rows(events: [event("Service", on: date(2026, 8, 1), due: date(2026, 8, 12))])
        XCTAssertTrue(result.first?.isLate == true)
    }

    func testFutureDueRecordIsNotLate() {
        let result = rows(events: [event("Service", on: date(2026, 8, 1), due: date(2026, 8, 20))])
        XCTAssertFalse(result.first?.isLate == true)
    }

    /// Same lower bound as `ThingsDigest`/`TimelineDigest`, so the badge here agrees with the
    /// "Late" badge on the Things row above it.
    func testStaleOverdueStopsBeingLate() {
        let result = rows(events: [event("Service", on: date(2026, 7, 1), due: date(2026, 8, 1), messageDaysAfter: 7)])
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result.first?.isLate == true)
    }

    func testUnwatchedRecordIsNeverLate() {
        let result = rows(events: [event("Service", on: date(2026, 1, 1))])
        XCTAssertFalse(result.first?.isLate == true)
        XCTAssertFalse(result.first?.isWatched == true)
    }

    // MARK: - Ordering

    func testLateRowsSortFirst() {
        let result = rows(events: [
            event("Fine", on: date(2026, 8, 14)),
            event("Overdue", on: date(2026, 8, 1), due: date(2026, 8, 12)),
        ])
        XCTAssertEqual(result.first?.title, "Overdue")
    }

    func testRecurringSortsAboveOneOffWhenNeitherIsLate() {
        let result = rows(events: [
            event("One-off", on: date(2026, 8, 14)),
            event("Monthly", on: date(2026, 8, 1), recurrence: .monthly, seriesID: UUID()),
        ])
        XCTAssertEqual(result.map(\.title), ["Monthly", "One-off"])
    }

    func testNewestDateFirstWithinTheSameClass() {
        let result = rows(events: [
            event("Older", on: date(2026, 7, 1)),
            event("Newer", on: date(2026, 8, 1)),
        ])
        XCTAssertEqual(result.map(\.title), ["Newer", "Older"])
    }

    func testEmptyInputGivesNoRows() {
        XCTAssertTrue(rows().isEmpty)
    }
}
