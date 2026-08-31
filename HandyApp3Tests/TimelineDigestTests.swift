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
                       messageDaysBefore: Int = DueDefaults.messageDaysBefore,
                       messageDaysAfter: Int = DueDefaults.messageDaysAfter) -> Event {
        Event(title: "Event", date: date(2026, 8, 1), recurrence: recurrence, dueDate: dueDate,
              seriesID: seriesID, createdAt: createdAt, messageDaysBefore: messageDaysBefore,
              messageDaysAfter: messageDaysAfter)
    }

    private func transaction(dueDate: Date?, amount: Decimal = 100, kind: TransactionKind = .expense,
                             recurrence: RecurrenceInterval? = nil,
                             messageDaysBefore: Int = DueDefaults.messageDaysBefore,
                             details: String = "Txn", occurredOn: Date? = nil) -> Transaction {
        Transaction(details: details, amount: amount, date: occurredOn ?? date(2026, 8, 1), kind: kind,
                    recurrence: recurrence, dueDate: dueDate, createdAt: Date(timeIntervalSince1970: 0),
                    messageDaysBefore: messageDaysBefore)
    }

    private func source(events: [Event] = [], transactions: [Transaction] = [], name: String = "Thing") -> TimelineSource {
        TimelineSource(assetID: UUID(), assetName: name, events: events, transactions: transactions)
    }

    private func items(_ sources: [TimelineSource]) -> [TimelineItem] {
        TimelineDigest.items(sources: sources, calendar: calendar, now: now)
    }

    private func summary(_ sources: [TimelineSource]) -> TimelineSummary {
        TimelineDigest.summary(from: items(sources), sources: sources, calendar: calendar, now: now)
    }

    private func entries(_ sources: [TimelineSource]) -> [CashFlowEntry] {
        TimelineDigest.cashFlowEntries(sources: sources, calendar: calendar, now: now)
    }

    private func cashFlow(_ sources: [TimelineSource]) -> Decimal {
        TimelineDigest.recentCashFlow(sources: sources, calendar: calendar, now: now)
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

        let result = summary([source(events: [upcomingEvent], transactions: [overdue, expense, income])])
        XCTAssertEqual(result.overdueCount, 1)
        // Overdue is excluded from both forward-looking figures. Of the three remaining, only
        // the Aug 20 expense (5 days out) is inside the default 7-day lead — the Aug 25 event
        // and the Sep 1 income are still listed below, just not called out by the header.
        XCTAssertEqual(result.upcomingCount, 1)
        // Cash flow answers a different question entirely: all three transactions occurred on
        // Aug 1, two weeks back, so every one lands in the trailing window regardless of when
        // it was due. −50 − 200 + 500.
        XCTAssertEqual(result.recentCashFlow, 250)
    }

    func testDueTodayIsCountedAsDueSoon() {
        // Due today is not overdue, so if the lead-in window excluded its own due date this
        // record would fall through both header stats.
        let result = summary([source(events: [event(dueDate: now)])])
        XCTAssertEqual(result.overdueCount, 0)
        XCTAssertEqual(result.upcomingCount, 1)
    }

    func testDueSoonHonorsTheRecordsOwnLeadTime() {
        // Both 10 days out; only the one asking for a 14-day lead is called out.
        let shortLead = event(dueDate: date(2026, 8, 25), messageDaysBefore: 3)
        let longLead = event(dueDate: date(2026, 8, 25), messageDaysBefore: 14)
        XCTAssertEqual(summary([source(events: [shortLead])]).upcomingCount, 0)
        XCTAssertEqual(summary([source(events: [longLead])]).upcomingCount, 1)
    }

    func testDueSoonBoundaryIsInclusive() {
        // Lead of 5 with now = Aug 15: Aug 20 is exactly at the edge, Aug 21 one past it.
        let atEdge = event(dueDate: date(2026, 8, 20), messageDaysBefore: 5)
        let pastEdge = event(dueDate: date(2026, 8, 21), messageDaysBefore: 5)
        XCTAssertEqual(summary([source(events: [atEdge])]).upcomingCount, 1)
        XCTAssertEqual(summary([source(events: [pastEdge])]).upcomingCount, 0)
    }

    func testLeadTimeBeyondHorizonClampsToTheHorizon() {
        // The slider reaches 60 but the item pool stops at 31, so a 60-day lead can only start
        // counting once the record crosses the horizon. Documents the clamp rather than
        // endorsing it — see TimelineDigest.horizonDays.
        let beyond = event(dueDate: date(2026, 9, 16), messageDaysBefore: 60)   // 32 days out
        let atHorizon = event(dueDate: date(2026, 9, 15), messageDaysBefore: 60) // 31 days out
        XCTAssertEqual(summary([source(events: [beyond])]).upcomingCount, 0)
        XCTAssertEqual(summary([source(events: [atHorizon])]).upcomingCount, 1)
    }

    func testOverdueIsNeverCountedAsDueSoon() {
        let late = event(dueDate: date(2026, 8, 13), messageDaysBefore: 60)
        let result = summary([source(events: [late])])
        XCTAssertEqual(result.overdueCount, 1)
        XCTAssertEqual(result.upcomingCount, 0)
    }

    // MARK: - Recent cash flow

    func testCashFlowUsesOccurrenceDateNotDueDate() {
        // Occurred three weeks ago, not due for another two — money already spent.
        let paid = transaction(dueDate: date(2026, 9, 1), amount: 400, occurredOn: date(2026, 7, 25))
        XCTAssertEqual(cashFlow([source(transactions: [paid])]), -400)
    }

    func testCashFlowCountsRecordsWithNoDueDate() {
        // Invisible to every other part of this screen, but it is still money that moved.
        let fuel = transaction(dueDate: nil, amount: 86, occurredOn: date(2026, 8, 10))
        XCTAssertTrue(items([source(transactions: [fuel])]).isEmpty)
        XCTAssertEqual(cashFlow([source(transactions: [fuel])]), -86)
    }

    func testCashFlowWindowReachesBackExactlyAsFarAsTheHorizonReachesForward() {
        // now = Aug 15, horizonDays = 31, so Jul 15 is the oldest day that counts.
        let oldest = transaction(dueDate: nil, amount: 10, occurredOn: date(2026, 7, 15))
        let tooOld = transaction(dueDate: nil, amount: 10, occurredOn: date(2026, 7, 14))
        XCTAssertEqual(cashFlow([source(transactions: [oldest])]), -10)
        XCTAssertEqual(cashFlow([source(transactions: [tooOld])]), 0)
    }

    func testCashFlowIncludesTodayButNotTheFuture() {
        let today = transaction(dueDate: nil, amount: 25, occurredOn: now)
        let tomorrow = transaction(dueDate: nil, amount: 25, occurredOn: date(2026, 8, 16))
        XCTAssertEqual(cashFlow([source(transactions: [today])]), -25)
        XCTAssertEqual(cashFlow([source(transactions: [tomorrow])]), 0)
    }

    func testCashFlowIgnoresEvents() {
        XCTAssertEqual(cashFlow([source(events: [event(dueDate: date(2026, 8, 20))])]), 0)
    }

    // MARK: - Cash flow entries

    func testEntriesAreOrderedByAbsoluteAmountDescending() {
        // Biggest movement first whichever way it went: the 1140 expense outranks the 62
        // expense *and* sits above it despite both being negative. Date order is deliberately
        // scrambled against amount order so only the amount rule can produce this result.
        let paycheck = transaction(dueDate: nil, amount: 3100, kind: .income, details: "Paycheck",
                                   occurredOn: date(2026, 7, 20))
        let big = transaction(dueDate: nil, amount: 1140, details: "Insurance",
                              occurredOn: date(2026, 8, 12))
        let small = transaction(dueDate: nil, amount: 62, details: "Fuel", occurredOn: date(2026, 8, 2))
        XCTAssertEqual(entries([source(transactions: [big, small, paycheck])]).map(\.details),
                       ["Paycheck", "Insurance", "Fuel"])
    }

    func testAnExpenseOutranksSmallerIncome() {
        // The rule that separates this from signed ordering: a big expense must not sink below
        // every scrap of income.
        let tip = transaction(dueDate: nil, amount: 20, kind: .income, details: "Refund",
                              occurredOn: date(2026, 8, 9))
        let repair = transaction(dueDate: nil, amount: 2400, details: "Repair", occurredOn: date(2026, 8, 9))
        XCTAssertEqual(entries([source(transactions: [tip, repair])]).map(\.details),
                       ["Repair", "Refund"])
    }

    func testEqualMagnitudeOrdersIncomeBeforeExpense() {
        let inbound = transaction(dueDate: nil, amount: 500, kind: .income, details: "In",
                                  occurredOn: date(2026, 8, 9))
        let outbound = transaction(dueDate: nil, amount: 500, details: "Out", occurredOn: date(2026, 8, 9))
        XCTAssertEqual(entries([source(transactions: [outbound, inbound])]).map(\.details),
                       ["In", "Out"])
    }

    func testEqualAmountsFallBackToNewestOccurrenceFirst() {
        // Two occurrences of the same recurring bill land on the same amount and the same sign,
        // so the date tiebreak is what keeps them in a stable, meaningful order.
        let older = transaction(dueDate: nil, amount: 120, details: "July", occurredOn: date(2026, 7, 18))
        let newer = transaction(dueDate: nil, amount: 120, details: "August", occurredOn: date(2026, 8, 14))
        XCTAssertEqual(entries([source(transactions: [older, newer])]).map(\.details),
                       ["August", "July"])
    }

    /// The invariant that keeps the header pill and the list behind it honest: the figure is
    /// the sum of exactly the rows shown.
    func testCashFlowEqualsTheSumOfItsEntries() {
        let sources = [
            source(transactions: [transaction(dueDate: nil, amount: 3100, kind: .income,
                                              occurredOn: date(2026, 8, 3)),
                                  transaction(dueDate: nil, amount: 1140, occurredOn: date(2026, 8, 4))],
                   name: "House"),
            source(transactions: [transaction(dueDate: date(2026, 8, 20), amount: 62,
                                              occurredOn: date(2026, 7, 30))], name: "Car")
        ]
        XCTAssertEqual(entries(sources).count, 3)
        XCTAssertEqual(entries(sources).reduce(Decimal(0)) { $0 + $1.signedAmount }, cashFlow(sources))
        XCTAssertEqual(cashFlow(sources), 1898)
    }

    func testEntriesCarryTheOwningAssetName() {
        // Distinct amounts so the assertion pins the asset name, not the sort.
        let sources = [
            source(transactions: [transaction(dueDate: nil, amount: 50, details: "Roof",
                                              occurredOn: date(2026, 8, 5))], name: "House"),
            source(transactions: [transaction(dueDate: nil, amount: 900, details: "Tires",
                                              occurredOn: date(2026, 8, 6))], name: "Car")
        ]
        // 900 outranks 50 on magnitude.
        XCTAssertEqual(entries(sources).map(\.assetName), ["Car", "House"])
    }

    func testEntriesKeepBothSeriesMembersRatherThanSuppressingOne() {
        // The logged occurrence and the one that superseded it are two real payments; the
        // suppression rule that hides one from "Coming up" must not net it away here.
        let seriesID = UUID()
        let logged = transaction(dueDate: date(2026, 8, 1), amount: 120, recurrence: .monthly,
                                 occurredOn: date(2026, 8, 1))
        let next = transaction(dueDate: date(2026, 9, 1), amount: 120, recurrence: .monthly,
                               occurredOn: date(2026, 8, 14))
        logged.seriesID = seriesID
        next.seriesID = seriesID
        let source = source(transactions: [logged, next])
        // Collapsed to a single row on the timeline…
        XCTAssertEqual(items([source]).count, 1)
        // …but both payments are their own entry, and both count.
        XCTAssertEqual(entries([source]).count, 2)
        XCTAssertEqual(cashFlow([source]), -240)
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
