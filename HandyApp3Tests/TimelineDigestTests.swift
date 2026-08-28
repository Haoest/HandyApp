import XCTest
@testable import HandyApp3

final class TimelineDigestTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    /// Fixed "now" so bucket math is independent of the real clock.
    private var now: Date { date(2026, 8, 15) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(dueDate: Date?, recurrence: RecurrenceInterval? = nil, seriesID: UUID? = nil,
                       createdAt: Date = Date(timeIntervalSince1970: 0),
                       messageDaysAfter: Int = DueDefaults.messageDaysAfter) -> Event {
        Event(title: "Event", date: date(2026, 8, 1), recurrence: recurrence, dueDate: dueDate,
              seriesID: seriesID, createdAt: createdAt, messageDaysAfter: messageDaysAfter)
    }

    private func transaction(dueDate: Date?, amount: Decimal = 100, kind: TransactionKind = .expense,
                             recurrence: RecurrenceInterval? = nil) -> Transaction {
        Transaction(details: "Txn", amount: amount, date: date(2026, 8, 1), kind: kind,
                    recurrence: recurrence, dueDate: dueDate, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func source(events: [Event] = [], transactions: [Transaction] = [], name: String = "Thing") -> TimelineSource {
        TimelineSource(assetID: UUID(), assetName: name, events: events, transactions: transactions)
    }

    private func items(_ sources: [TimelineSource]) -> [TimelineItem] {
        TimelineDigest.items(sources: sources, calendar: calendar, now: now)
    }

    // MARK: - Membership

    func testRecordWithoutDueDateIsNotWatched() {
        XCTAssertTrue(items([source(events: [event(dueDate: nil)])]).isEmpty)
    }

    func testRecordBeyondHorizonIsExcluded() {
        // 32 days out — one past the 31-day horizon.
        XCTAssertTrue(items([source(events: [event(dueDate: date(2026, 9, 16))])]).isEmpty)
    }

    func testRecordAtHorizonBoundaryIsIncluded() {
        let result = items([source(events: [event(dueDate: date(2026, 9, 15))])])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.daysUntilDue, TimelineDigest.horizonDays)
    }

    /// The lead-time slider deliberately no longer gates membership — a record due well beyond
    /// its `messageDaysBefore` still populates the forward windows.
    func testLeadTimeDoesNotGateMembership() {
        let e = Event(title: "Event", date: date(2026, 8, 1), dueDate: date(2026, 9, 10),
                      createdAt: Date(timeIntervalSince1970: 0), messageDaysBefore: 1)
        XCTAssertEqual(items([source(events: [e])]).count, 1)
    }

    /// `messageDaysAfter` is still honored, so a long-ignored overdue record stops nagging.
    func testOverdueBeyondPostDueWindowIsDropped() {
        let stale = event(dueDate: date(2026, 8, 1), messageDaysAfter: 7)   // 14 days late
        let fresh = event(dueDate: date(2026, 8, 10), messageDaysAfter: 7)  // 5 days late
        let result = items([source(events: [stale, fresh])])
        XCTAssertEqual(result.map(\.id), [fresh.id])
    }

    // MARK: - Buckets

    func testBucketBoundaries() {
        XCTAssertEqual(TimelineWindow.containing(daysUntilDue: -1), .overdue)
        XCTAssertEqual(TimelineWindow.containing(daysUntilDue: 0), .thisWeek)
        XCTAssertEqual(TimelineWindow.containing(daysUntilDue: 7), .thisWeek)
        XCTAssertEqual(TimelineWindow.containing(daysUntilDue: 8), .nextTwoWeeks)
        XCTAssertEqual(TimelineWindow.containing(daysUntilDue: 14), .nextTwoWeeks)
        XCTAssertEqual(TimelineWindow.containing(daysUntilDue: 15), .laterThisMonth)
        XCTAssertEqual(TimelineWindow.containing(daysUntilDue: 31), .laterThisMonth)
        XCTAssertNil(TimelineWindow.containing(daysUntilDue: 32))
    }

    func testGroupsAreOrderedAndEmptyWindowsOmitted() {
        let overdue = event(dueDate: date(2026, 8, 13))
        let later = event(dueDate: date(2026, 9, 5))
        let groups = TimelineDigest.groups(from: items([source(events: [later, overdue])]))
        XCTAssertEqual(groups.map(\.window), [.overdue, .laterThisMonth])
    }

    func testItemsSortedBySoonestDueFirst() {
        let a = event(dueDate: date(2026, 9, 1))
        let b = event(dueDate: date(2026, 8, 20))
        let c = event(dueDate: date(2026, 8, 14))
        XCTAssertEqual(items([source(events: [a, b, c])]).map(\.id), [c.id, b.id, a.id])
    }

    // MARK: - Series collapsing

    func testSeriesCollapsesToOneRowRepresentedBySoonestDue() {
        let seriesID = UUID()
        let soonest = event(dueDate: date(2026, 8, 20), recurrence: .monthly, seriesID: seriesID,
                            createdAt: Date(timeIntervalSince1970: 100))
        let later = event(dueDate: date(2026, 9, 10), recurrence: .monthly, seriesID: seriesID,
                          createdAt: Date(timeIntervalSince1970: 200))
        let result = items([source(events: [soonest, later])])
        XCTAssertEqual(result.count, 1)
        // Soonest member decides when the row appears…
        XCTAssertEqual(result.first?.id, soonest.id)
        // …but the newest-created member is what "Log it" acts on.
        XCTAssertEqual(result.first?.openRecordID, later.id)
    }

    func testRecordsWithoutSeriesAreNotCollapsedTogether() {
        let a = event(dueDate: date(2026, 8, 20))
        let b = event(dueDate: date(2026, 8, 21))
        XCTAssertEqual(items([source(events: [a, b])]).count, 2)
    }

    // MARK: - Summary

    func testSummaryCountsAndNets() {
        let overdue = transaction(dueDate: date(2026, 8, 13), amount: 50)
        let expense = transaction(dueDate: date(2026, 8, 20), amount: 200)
        let income = transaction(dueDate: date(2026, 9, 1), amount: 500, kind: .income)
        let upcomingEvent = event(dueDate: date(2026, 8, 25))

        let summary = TimelineDigest.summary(
            from: items([source(events: [upcomingEvent], transactions: [overdue, expense, income])])
        )
        XCTAssertEqual(summary.overdueCount, 1)
        // Overdue is excluded from the forward-looking count and net.
        XCTAssertEqual(summary.upcomingCount, 3)
        XCTAssertEqual(summary.netAmount, 300)
    }

    func testWindowNetIgnoresEventsButCountsThem() {
        let expense = transaction(dueDate: date(2026, 8, 18), amount: 75)
        let e = event(dueDate: date(2026, 8, 19))
        let group = TimelineDigest.groups(from: items([source(events: [e], transactions: [expense])])).first
        XCTAssertEqual(group?.window, .thisWeek)
        XCTAssertEqual(group?.items.count, 2)
        XCTAssertTrue(group?.hasMoney == true)
        XCTAssertEqual(group?.netAmount, -75)
    }

    func testWindowWithOnlyEventsHasNoMoney() {
        let group = TimelineDigest.groups(from: items([source(events: [event(dueDate: date(2026, 8, 18))])])).first
        XCTAssertFalse(group?.hasMoney == true)
        XCTAssertEqual(group?.netAmount, 0)
    }

    // MARK: - Cross-asset

    func testItemsSpanAssetsAndCarryOwnerNames() {
        let houseEvent = event(dueDate: date(2026, 8, 18))
        let carEvent = event(dueDate: date(2026, 8, 17))
        let result = items([
            source(events: [houseEvent], name: "House"),
            source(events: [carEvent], name: "Car"),
        ])
        XCTAssertEqual(result.map(\.assetName), ["Car", "House"])
    }
}
