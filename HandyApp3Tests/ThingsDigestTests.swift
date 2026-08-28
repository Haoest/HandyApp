import XCTest
@testable import HandyApp3

final class ThingsDigestTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private var now: Date { date(2026, 8, 15) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(dueDate: Date? = nil, messageDaysAfter: Int = DueDefaults.messageDaysAfter) -> Event {
        Event(title: "Event", date: date(2026, 8, 1), dueDate: dueDate,
              createdAt: Date(timeIntervalSince1970: 0), messageDaysAfter: messageDaysAfter)
    }

    private func transaction(dueDate: Date? = nil) -> Transaction {
        Transaction(details: "Txn", amount: 10, date: date(2026, 8, 1), kind: .expense,
                    dueDate: dueDate, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func facts(events: [Event] = [], transactions: [Transaction] = [],
                       amounts: [(date: Date, signedAmount: Decimal)] = []) -> ThingFacts {
        ThingsDigest.facts(events: events, transactions: transactions,
                           transactionAmounts: amounts, calendar: calendar, now: now)
    }

    // MARK: - Next due

    func testNoDueDatesGivesNoNextDue() {
        let result = facts(events: [event()], transactions: [transaction()])
        XCTAssertNil(result.nextDue)
        XCTAssertFalse(result.isLate)
        XCTAssertEqual(result.recordCount, 2)
    }

    func testNextDueIsTheSoonestUpcoming() {
        let result = facts(events: [event(dueDate: date(2026, 9, 20)), event(dueDate: date(2026, 8, 30))])
        XCTAssertEqual(result.nextDue, date(2026, 8, 30))
    }

    /// The Timeline stops at 31 days; a Things row deliberately does not.
    func testNextDueIgnoresTheTimelineHorizon() {
        let farOut = date(2027, 4, 2)
        XCTAssertEqual(facts(events: [event(dueDate: farOut)]).nextDue, farOut)
    }

    func testNextDueSpansEventsAndTransactions() {
        let result = facts(events: [event(dueDate: date(2026, 9, 1))],
                           transactions: [transaction(dueDate: date(2026, 8, 20))])
        XCTAssertEqual(result.nextDue, date(2026, 8, 20))
    }

    // MARK: - Late

    func testOverdueRecordMarksThingLate() {
        let result = facts(events: [event(dueDate: date(2026, 8, 12))])
        XCTAssertTrue(result.isLate)
        XCTAssertEqual(result.nextDue, date(2026, 8, 12))
    }

    /// An overdue record outranks a nearer upcoming one, so "Next" names what needs attention.
    func testOverduePreemptsUpcomingInNextDue() {
        let result = facts(events: [event(dueDate: date(2026, 8, 16)), event(dueDate: date(2026, 8, 12))])
        XCTAssertTrue(result.isLate)
        XCTAssertEqual(result.nextDue, date(2026, 8, 12))
    }

    /// Matches the Timeline's lower bound, so the two screens agree about what "late" means.
    func testStaleOverdueStopsCountingAsLate() {
        let result = facts(events: [event(dueDate: date(2026, 8, 1), messageDaysAfter: 7)])
        XCTAssertFalse(result.isLate)
        XCTAssertNil(result.nextDue)
    }

    // MARK: - Trailing 12-month net

    func testNetSumsOnlyTheTrailingTwelveMonths() {
        let result = facts(amounts: [
            (date: date(2026, 8, 1), signedAmount: -100),
            (date: date(2026, 1, 1), signedAmount: -50),
            (date: date(2025, 6, 1), signedAmount: -9999),   // older than 12 months
        ])
        XCTAssertEqual(result.netLast12Months, -150)
    }

    func testNetOffsetsIncomeAgainstExpense() {
        let result = facts(amounts: [
            (date: date(2026, 8, 1), signedAmount: -400),
            (date: date(2026, 8, 2), signedAmount: 1000),
        ])
        XCTAssertEqual(result.netLast12Months, 600)
    }

    func testNetIsZeroWithoutTransactions() {
        XCTAssertEqual(facts(events: [event()]).netLast12Months, 0)
    }

    // MARK: - Spec line

    func testSpecJoinsFilledValuesUpToLimit() {
        let spec = ThingsDigest.spec(from: [.text("Ferrari"), .text("Testarossa"), .number(1985), .text("FASTEST")])
        XCTAssertEqual(spec, "Ferrari · Testarossa · 1,985")
    }

    func testSpecSkipsContactsBlanksAndData() {
        let spec = ThingsDigest.spec(from: [.contact("abc"), .text("   "), .data(Data()), .text("Carrier")])
        XCTAssertEqual(spec, "Carrier")
    }

    func testSpecIsEmptyWhenNothingIsFilledIn() {
        XCTAssertEqual(ThingsDigest.spec(from: []), "")
    }
}
