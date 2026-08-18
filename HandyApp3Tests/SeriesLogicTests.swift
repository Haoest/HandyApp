import XCTest
@testable import HandyApp3

final class SeriesLogicTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - duplicateTitle

    func testDuplicateTitlePlainAppendsYearMonth() {
        let title = SeriesLogic.duplicateTitle(source: "Rent", seriesTitles: [], creationDate: date(2026, 8, 15), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-08")
    }

    // a stale month stamp (from a prior duplication) is replaced with the current month,
    // unstamped — a new month starts fresh, it doesn't inherit the old month's count
    func testDuplicateTitleReplacesStaleMonthWithCurrentMonth() {
        let title = SeriesLogic.duplicateTitle(source: "Rent 2026-01", seriesTitles: [], creationDate: date(2026, 8, 15), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-08")
    }

    // a stale month's own "(n)" suffix is dropped along with the stale month, not carried
    // forward into the fresh, unstamped current month
    func testDuplicateTitleReplacingStaleMonthDropsItsSuffix() {
        let title = SeriesLogic.duplicateTitle(source: "Rent 2026-01 (2)", seriesTitles: [], creationDate: date(2026, 8, 15), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-08")
    }

    // duplicating again within the same month as the existing stamp, with no prior same-month
    // duplicate on record, gets tag "(1)" — not "(2)": nothing before it claimed a number
    func testDuplicateTitleSameMonthFirstDuplicateGetsTagOne() {
        let title = SeriesLogic.duplicateTitle(source: "Rent 2026-08", seriesTitles: [], creationDate: date(2026, 8, 15), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-08 (1)")
    }

    // duplicating again within the same month as an already-numbered stamp strips that number
    // and recomputes its own, one past what's already there
    func testDuplicateTitleSameMonthStripsExistingSuffixBeforeReappending() {
        let title = SeriesLogic.duplicateTitle(source: "Rent 2026-01 (2)", seriesTitles: [], creationDate: date(2026, 1, 20), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-01 (3)")
    }

    // the next same-month tag is one past the highest "(n)" already on record for that month
    // across every live series member, not just `source`
    func testDuplicateTitleSameMonthIncrementsPastHighestExistingSuffix() {
        let title = SeriesLogic.duplicateTitle(source: "Rent 2026-01", seriesTitles: ["Rent 2026-01 (3)", "Rent 2026-01 (2)"], creationDate: date(2026, 1, 15), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-01 (4)")
    }

    func testDuplicateTitleInvalidMonthDoesNotMatchYearMonthPattern() {
        // "2026-13" has no valid month, so the yyyy-MM check fails and the date suffix appends.
        let title = SeriesLogic.duplicateTitle(source: "Rent 2026-13", seriesTitles: [], creationDate: date(2026, 8, 15), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-13 2026-08")
    }

    // the yyyy-MM stamp need not be at the very end of the description to be found and replaced
    func testDuplicateTitleReplacesStaleMonthInMiddleOfDescription() {
        let title = SeriesLogic.duplicateTitle(source: "Rent 2026-01 payment", seriesTitles: [], creationDate: date(2026, 8, 15), calendar: calendar)
        XCTAssertEqual(title, "Rent 2026-08 payment")
    }

    // MARK: - members / newest

    func testMembersOrderedByCreatedAtDescending() {
        let a = Event(title: "A", date: date(2026, 1, 1), createdAt: date(2026, 1, 1))
        let b = Event(title: "B", date: date(2026, 1, 1), createdAt: date(2026, 3, 1))
        let c = Event(title: "C", date: date(2026, 1, 1), createdAt: date(2026, 2, 1))
        let seriesID = UUID()
        a.seriesID = seriesID; b.seriesID = seriesID; c.seriesID = seriesID
        let all = [a, b, c]
        XCTAssertEqual(SeriesLogic.members(of: a, in: all).map(\.title), ["B", "C", "A"])
        XCTAssertEqual(SeriesLogic.newest(of: a, in: all).title, "B")
    }

    func testMembersTieBreaksByIdDescendingOnSameSecond() {
        let sharedInstant = date(2026, 1, 1)
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let a = Event(id: lowID, title: "Low", date: sharedInstant, createdAt: sharedInstant)
        let b = Event(id: highID, title: "High", date: sharedInstant, createdAt: sharedInstant)
        let seriesID = UUID()
        a.seriesID = seriesID; b.seriesID = seriesID
        let all = [a, b]
        XCTAssertEqual(SeriesLogic.newest(of: a, in: all).title, "High")
    }

    func testNoSeriesIsSingletonMembership() {
        let a = Event(title: "A", date: date(2026, 1, 1))
        let b = Event(title: "B", date: date(2026, 1, 1))
        XCTAssertEqual(SeriesLogic.members(of: a, in: [a, b]).map(\.title), ["A"])
        XCTAssertEqual(SeriesLogic.newest(of: a, in: [a, b]).title, "A")
    }

    // MARK: - isSuppressed

    func testSuppressedWhenNewerSiblingWithinCurrentPeriod() {
        // Monthly record due Feb 1; a sibling created after Jan 1 (D - I) suppresses it.
        let older = Event(title: "Old", date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 2, 1), seriesID: UUID(), createdAt: date(2026, 1, 5))
        let newer = Event(title: "New", date: date(2026, 1, 1), seriesID: older.seriesID, createdAt: date(2026, 1, 20))
        XCTAssertTrue(SeriesLogic.isSuppressed(older, in: [older, newer], calendar: calendar))
    }

    func testNotSuppressedWhenSiblingCreatedBeforePeriodStart() {
        // Sibling created well before D - I (Jan 1) does not suppress.
        let record = Event(title: "R", date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 2, 1), seriesID: UUID(), createdAt: date(2026, 1, 5))
        let earlySibling = Event(title: "Early", date: date(2025, 1, 1), seriesID: record.seriesID, createdAt: date(2025, 12, 1))
        XCTAssertFalse(SeriesLogic.isSuppressed(record, in: [record, earlySibling], calendar: calendar))
    }

    func testNotSuppressedByOlderSameSeriesMember() {
        let seriesID = UUID()
        let source = Event(title: "Source", date: date(2026, 1, 1), seriesID: seriesID, createdAt: date(2026, 1, 1))
        let record = Event(title: "R", date: date(2026, 2, 1), recurrence: .monthly, dueDate: date(2026, 3, 1), seriesID: seriesID, createdAt: date(2026, 2, 1))
        XCTAssertFalse(SeriesLogic.isSuppressed(record, in: [source, record], calendar: calendar))
    }

    func testNilRecurrenceAnyNewerSiblingSuppresses() {
        let seriesID = UUID()
        let record = Event(title: "R", date: date(2026, 1, 1), dueDate: date(2026, 2, 1), seriesID: seriesID, createdAt: date(2026, 1, 1))
        let newer = Event(title: "New", date: date(2026, 1, 1), seriesID: seriesID, createdAt: date(2026, 1, 2))
        XCTAssertTrue(SeriesLogic.isSuppressed(record, in: [record, newer], calendar: calendar))
    }

    func testNonSeriesRecordNeverSuppressed() {
        let record = Event(title: "R", date: date(2026, 1, 1), dueDate: date(2026, 2, 1))
        XCTAssertFalse(SeriesLogic.isSuppressed(record, in: [record], calendar: calendar))
    }

    // MARK: - isDueMessageActive

    func testDueMessageActiveExactlyAtBeforeBoundary() {
        let record = Event(title: "R", date: date(2026, 1, 1), dueDate: date(2026, 1, 15), messageDaysBefore: 7, messageDaysAfter: 7)
        XCTAssertTrue(SeriesLogic.isDueMessageActive(record, calendar: calendar, now: date(2026, 1, 8)))
    }

    func testDueMessageInactiveOneDayBeforeBoundary() {
        let record = Event(title: "R", date: date(2026, 1, 1), dueDate: date(2026, 1, 15), messageDaysBefore: 7, messageDaysAfter: 7)
        XCTAssertFalse(SeriesLogic.isDueMessageActive(record, calendar: calendar, now: date(2026, 1, 7)))
    }

    func testDueMessageActiveExactlyAtAfterBoundary() {
        let record = Event(title: "R", date: date(2026, 1, 1), dueDate: date(2026, 1, 15), messageDaysBefore: 7, messageDaysAfter: 7)
        XCTAssertTrue(SeriesLogic.isDueMessageActive(record, calendar: calendar, now: date(2026, 1, 22)))
    }

    func testDueMessageInactiveOneDayAfterBoundary() {
        let record = Event(title: "R", date: date(2026, 1, 1), dueDate: date(2026, 1, 15), messageDaysBefore: 7, messageDaysAfter: 7)
        XCTAssertFalse(SeriesLogic.isDueMessageActive(record, calendar: calendar, now: date(2026, 1, 23)))
    }

    func testDueMessageInactiveWithNoDueDate() {
        let record = Event(title: "R", date: date(2026, 1, 1))
        XCTAssertFalse(SeriesLogic.isDueMessageActive(record, calendar: calendar, now: date(2026, 1, 1)))
    }

    // MARK: - advancedDueDate

    func testAdvancedDueDateAdvancesRecurringSourceByOneInterval() {
        let source = Event(title: "Rent", date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 2, 1))
        XCTAssertEqual(SeriesLogic.advancedDueDate(for: source, calendar: calendar), date(2026, 3, 1))
    }

    func testAdvancedDueDateCopiesVerbatimForNonRecurringSource() {
        let source = Event(title: "One-off", date: date(2026, 1, 1), dueDate: date(2026, 2, 1))
        XCTAssertEqual(SeriesLogic.advancedDueDate(for: source, calendar: calendar), date(2026, 2, 1))
    }

    func testAdvancedDueDateNilWhenNoDueDate() {
        let source = Event(title: "X", date: date(2026, 1, 1), recurrence: .monthly)
        XCTAssertNil(SeriesLogic.advancedDueDate(for: source, calendar: calendar))
    }
}
