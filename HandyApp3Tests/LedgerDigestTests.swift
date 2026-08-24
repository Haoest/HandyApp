import XCTest
@testable import HandyApp3

final class LedgerDigestTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(date: Date, recurrence: RecurrenceInterval? = nil, dueDate: Date? = nil,
                        seriesID: UUID? = nil, createdAt: Date = Date(timeIntervalSince1970: 0)) -> Event {
        Event(title: "Event", date: date, recurrence: recurrence, dueDate: dueDate, seriesID: seriesID, createdAt: createdAt)
    }

    private func transaction(date: Date, recurrence: RecurrenceInterval? = nil, dueDate: Date? = nil,
                              seriesID: UUID? = nil, createdAt: Date = Date(timeIntervalSince1970: 0),
                              kind: TransactionKind = .expense) -> Transaction {
        Transaction(details: "Txn", amount: 10, date: date, kind: kind, recurrence: recurrence,
                    dueDate: dueDate, seriesID: seriesID, createdAt: createdAt)
    }

    // Fixed "now" for window/late math, independent of the real clock.
    private var fixedNow: Date { date(2026, 8, 15) }

    // MARK: - Non-recurring window

    func testNonRecurringWithinWindowIncluded() {
        let e = event(date: date(2026, 6, 1))
        let result = LedgerDigest.select([e], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(result.nonRecurring.map(\.id), [e.id])
        XCTAssertTrue(result.recurring.isEmpty)
    }

    func testNonRecurringOlderThanWindowExcluded() {
        let e = event(date: date(2026, 1, 1))
        let result = LedgerDigest.select([e], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertTrue(result.nonRecurring.isEmpty)
    }

    func testWindowBoundaryIsInclusive() {
        let cutoff = calendar.date(byAdding: .month, value: -6, to: calendar.startOfDay(for: fixedNow))!
        let e = event(date: cutoff)
        let result = LedgerDigest.select([e], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(result.nonRecurring.map(\.id), [e.id])
    }

    func testCustomWindowMonthsRespected() {
        let e = event(date: date(2026, 6, 1))
        let wide = LedgerDigest.select([e], windowMonths: 6, calendar: calendar, now: fixedNow)
        let narrow = LedgerDigest.select([e], windowMonths: 1, calendar: calendar, now: fixedNow)
        XCTAssertEqual(wide.nonRecurring.map(\.id), [e.id])
        XCTAssertTrue(narrow.nonRecurring.isEmpty)
    }

    // MARK: - Recurring series selection

    func testRecurringOldOccurrenceIncludedRegardlessOfAge() {
        // Far outside any reasonable window, but it's the only (and therefore newest) member.
        let e = event(date: date(2018, 1, 1), recurrence: .monthly, dueDate: date(2018, 2, 1))
        let result = LedgerDigest.select([e], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(result.recurring.map(\.record.id), [e.id])
    }

    func testNewestPerSeriesPickedByCreatedAt() {
        let series = UUID()
        let older = event(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 2, 1),
                          seriesID: series, createdAt: date(2026, 1, 1))
        let newer = event(date: date(2026, 2, 1), recurrence: .monthly, dueDate: date(2026, 3, 1),
                          seriesID: series, createdAt: date(2026, 2, 1))
        let result = LedgerDigest.select([older, newer], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(result.recurring.map(\.record.id), [newer.id])
    }

    func testNilSeriesIDSingletonsAllIncluded() {
        let a = event(date: date(2018, 1, 1), recurrence: .monthly, dueDate: date(2018, 2, 1))
        let b = event(date: date(2018, 1, 1), recurrence: .weekly, dueDate: date(2018, 1, 8))
        let result = LedgerDigest.select([a, b], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(Set(result.recurring.map(\.record.id)), Set([a.id, b.id]))
    }

    func testMixedSeriesNonRecurringMemberWindowsIndividually() {
        let series = UUID()
        let recurringMember = event(date: date(2018, 1, 1), recurrence: .monthly, dueDate: date(2018, 2, 1), seriesID: series)
        let nonRecurringMemberInWindow = event(date: date(2026, 7, 1), recurrence: nil, seriesID: series)
        let result = LedgerDigest.select([recurringMember, nonRecurringMemberInWindow], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(result.recurring.map(\.record.id), [recurringMember.id])
        XCTAssertEqual(result.nonRecurring.map(\.id), [nonRecurringMemberInWindow.id])
    }

    // MARK: - Next expected / late

    // A stale due date is repaired for display: the record was dated forward to Aug 23 but
    // still carries its Jun 1 due date, so the quarterly grid rolls to Sep 1 rather than
    // reporting a "next occurrence" that already passed.
    func testNextExpectedRollsAStaleDueDatePastTheRecordsOwnDate() {
        let e = event(date: date(2026, 8, 23), recurrence: .quarterly, dueDate: date(2026, 6, 1))
        let facts = LedgerDigest.recurringFacts(for: e, calendar: calendar, now: fixedNow)
        XCTAssertEqual(facts?.nextExpected, date(2026, 9, 1))
    }

    // The mirror case: a due date already ahead of its record's date is shown as-is, never
    // advanced a second time. This is what a freshly logged occurrence looks like, since
    // `SeriesLogic.projectedDueDate` already rolled it forward at write time.
    func testNextExpectedLeavesAnAlreadyForwardDueDateAlone() {
        let e = event(date: date(2026, 8, 23), recurrence: .quarterly, dueDate: date(2026, 9, 1))
        let facts = LedgerDigest.recurringFacts(for: e, calendar: calendar, now: fixedNow)
        XCTAssertEqual(facts?.nextExpected, date(2026, 9, 1))
    }

    // Rolling is anchored on the record's own date, never on `now`, so a series that really is
    // overdue stays overdue instead of being quietly rolled into the future.
    func testNextExpectedDoesNotRollAnOverdueSeriesPastToday() {
        let e = event(date: date(2026, 1, 1), recurrence: .quarterly, dueDate: date(2026, 3, 1))
        let facts = LedgerDigest.recurringFacts(for: e, calendar: calendar, now: fixedNow)
        XCTAssertEqual(facts?.nextExpected, date(2026, 3, 1))
        XCTAssertEqual(facts?.isLate, true)
    }

    func testNextExpectedFallsBackToDatePlusIntervalWhenNoDueDate() {
        let monthly = event(date: date(2026, 1, 10), recurrence: .monthly, dueDate: nil)
        let weekly = event(date: date(2026, 1, 1), recurrence: .weekly, dueDate: nil)
        XCTAssertEqual(LedgerDigest.recurringFacts(for: monthly, calendar: calendar, now: fixedNow)?.nextExpected, date(2026, 2, 10))
        XCTAssertEqual(LedgerDigest.recurringFacts(for: weekly, calendar: calendar, now: fixedNow)?.nextExpected, date(2026, 1, 8))
    }

    func testLateWhenTodayStrictlyAfterNextExpectedDay() {
        // Next expected Aug 10, strictly before fixedNow (Aug 15).
        let e = event(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 8, 10))
        let facts = LedgerDigest.recurringFacts(for: e, calendar: calendar, now: fixedNow)
        XCTAssertEqual(facts?.isLate, true)
    }

    func testNotLateOnNextExpectedDayItself() {
        // Next expected Aug 15, exactly fixedNow — due today is not yet late.
        let e = event(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 8, 15))
        let facts = LedgerDigest.recurringFacts(for: e, calendar: calendar, now: fixedNow)
        XCTAssertEqual(facts?.isLate, false)
    }

    func testNotLateWhenNextExpectedInFuture() {
        let e = event(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 8, 20))
        let facts = LedgerDigest.recurringFacts(for: e, calendar: calendar, now: fixedNow)
        XCTAssertEqual(facts?.isLate, false)
    }

    // MARK: - Within-group sort

    func testRecurringFirstThenIntervalShortestFirstThenDateDescending() {
        let weekly = event(date: date(2026, 8, 1), recurrence: .weekly, dueDate: date(2026, 8, 8))
        let monthly = event(date: date(2026, 8, 1), recurrence: .monthly, dueDate: date(2026, 9, 1))
        let nonRecurringNewer = event(date: date(2026, 8, 10))
        let nonRecurringOlder = event(date: date(2026, 8, 5))
        let source = LedgerSource(assetID: UUID(), assetName: "Asset",
                                  events: [nonRecurringOlder, monthly, nonRecurringNewer, weekly],
                                  transactions: [])
        let groups = LedgerDigest.build(sources: [source], windowMonths: 6, calendar: calendar, now: fixedNow)
        let ids = groups.first!.entries.map(\.recordID)
        XCTAssertEqual(ids, [weekly.id, monthly.id, nonRecurringNewer.id, nonRecurringOlder.id])
    }

    func testEventsAndTransactionsInterleaveByDate() {
        let earlierTxn = transaction(date: date(2026, 8, 5))
        let laterEvent = event(date: date(2026, 8, 10))
        let source = LedgerSource(assetID: UUID(), assetName: "Asset", events: [laterEvent], transactions: [earlierTxn])
        let groups = LedgerDigest.build(sources: [source], windowMonths: 6, calendar: calendar, now: fixedNow)
        let ids = groups.first!.entries.map(\.recordID)
        XCTAssertEqual(ids, [laterEvent.id, earlierTxn.id])
    }

    // MARK: - Group ordering

    func testGroupsOrderedByNewestDateDescending() {
        let older = LedgerSource(assetID: UUID(), assetName: "Older Asset", events: [event(date: date(2026, 6, 1))], transactions: [])
        let newer = LedgerSource(assetID: UUID(), assetName: "Newer Asset", events: [event(date: date(2026, 8, 1))], transactions: [])
        let groups = LedgerDigest.build(sources: [older, newer], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(groups.map(\.assetName), ["Newer Asset", "Older Asset"])
    }

    func testGroupOrderTiebreaksByNameThenID() {
        let sameDate = date(2026, 8, 1)
        let bID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let aID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let b = LedgerSource(assetID: bID, assetName: "Alpha", events: [event(date: sameDate)], transactions: [])
        let a = LedgerSource(assetID: aID, assetName: "Alpha", events: [event(date: sameDate)], transactions: [])
        let groups = LedgerDigest.build(sources: [a, b], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(groups.map(\.assetID), [bID, aID])
    }

    func testEmptyGroupsAreDropped() {
        let noActivity = LedgerSource(assetID: UUID(), assetName: "Quiet Asset", events: [], transactions: [])
        let groups = LedgerDigest.build(sources: [noActivity], windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - Filters

    func testTypeFilterAllIncludesEverything() {
        let e = event(date: date(2026, 8, 1))
        let t = transaction(date: date(2026, 8, 1))
        let source = LedgerSource(assetID: UUID(), assetName: "Asset", events: [e], transactions: [t])
        let groups = LedgerDigest.build(sources: [source], typeFilter: .all, windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(groups.first!.entries.count, 2)
    }

    func testTypeFilterEventsOnly() {
        let e = event(date: date(2026, 8, 1))
        let t = transaction(date: date(2026, 8, 1))
        let source = LedgerSource(assetID: UUID(), assetName: "Asset", events: [e], transactions: [t])
        let groups = LedgerDigest.build(sources: [source], typeFilter: .eventsOnly, windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(groups.first!.entries.map(\.recordID), [e.id])
    }

    func testTypeFilterTransactionsOnly() {
        let e = event(date: date(2026, 8, 1))
        let t = transaction(date: date(2026, 8, 1))
        let source = LedgerSource(assetID: UUID(), assetName: "Asset", events: [e], transactions: [t])
        let groups = LedgerDigest.build(sources: [source], typeFilter: .transactionsOnly, windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(groups.first!.entries.map(\.recordID), [t.id])
    }

    func testLateOnlyKeepsOnlyLateEntriesAndDropsEmptyGroups() {
        let lateEvent = event(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 2, 1))
        let onTimeEvent = event(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 12, 1))
        let recentNonRecurring = event(date: date(2026, 8, 1))
        let lateAsset = LedgerSource(assetID: UUID(), assetName: "Late Asset", events: [lateEvent], transactions: [])
        let onTimeAsset = LedgerSource(assetID: UUID(), assetName: "On Time Asset", events: [onTimeEvent, recentNonRecurring], transactions: [])
        let groups = LedgerDigest.build(sources: [lateAsset, onTimeAsset], lateOnly: true, windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(groups.map(\.assetName), ["Late Asset"])
        XCTAssertEqual(groups.first!.entries.map(\.recordID), [lateEvent.id])
    }

    // Late-only is independent of, and combines with, the type filter — not one of its cases.
    func testLateOnlyCombinesIndependentlyWithTypeFilter() {
        let lateEvent = event(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 2, 1))
        let lateTransaction = transaction(date: date(2026, 1, 1), recurrence: .monthly, dueDate: date(2026, 2, 1))
        let source = LedgerSource(assetID: UUID(), assetName: "Asset", events: [lateEvent], transactions: [lateTransaction])
        let groups = LedgerDigest.build(sources: [source], typeFilter: .eventsOnly, lateOnly: true, windowMonths: 6, calendar: calendar, now: fixedNow)
        XCTAssertEqual(groups.first!.entries.map(\.recordID), [lateEvent.id])
    }
}
