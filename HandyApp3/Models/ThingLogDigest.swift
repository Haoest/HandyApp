import Foundation

/// One row in a thing's Log tab: an event or a transaction, with a series reduced to a single
/// entry. Money rows carry `signedAmount`; event rows leave it `nil`.
struct ThingLogRow: Identifiable {
    /// The record the row stands for — the newest member of its series, so editing, logging,
    /// and duplicating all act on the live end of the series rather than an old occurrence.
    let id: UUID
    let title: String
    let isEvent: Bool
    /// Negative for an expense, positive for income, `nil` for an event.
    let signedAmount: Decimal?
    let payeeContactID: String?
    /// The record's own date — when it happened.
    let date: Date
    /// Set only when the record is watched.
    let dueDate: Date?
    let interval: RecurrenceInterval?
    /// Past due and still inside its post-due message window. Same bound as
    /// `ThingsDigest`/`TimelineDigest`, so a row's badge agrees with the Things row above it.
    let isLate: Bool
    /// How many records the series holds, this one included. 1 for a one-off.
    let seriesCount: Int

    var recurs: Bool { interval != nil }
    var isWatched: Bool { dueDate != nil }
}

/// Builds the Log tab's rows for one thing.
///
/// **Series collapse to one row, unlike the Timeline.** `TimelineDigest` also drops a series
/// whose current occurrence has already been logged (`SeriesLogic.isSuppressed`) — right for a
/// due list, wrong here: a thing's Log tab is the record of what exists, so a series stays
/// visible whether or not this period's occurrence is already handled. The representative is
/// always the newest member, which is what "Log now" extends and "History" expands.
enum ThingLogDigest {

    static func rows(
        events: [Event], transactions: [Transaction],
        calendar: Calendar = .current, now: Date = Date()
    ) -> [ThingLogRow] {
        let today = calendar.startOfDay(for: now)

        func isLate<R: SeriesRecord>(_ record: R) -> Bool {
            guard let dueDate = record.dueDate,
                  let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: dueDate)).day
            else { return false }
            return days < 0 && days >= -record.messageDaysAfter
        }

        var result: [ThingLogRow] = []

        for group in collapse(events) {
            let record = group.newest
            result.append(ThingLogRow(
                id: record.id, title: record.title, isEvent: true,
                signedAmount: nil, payeeContactID: nil,
                date: record.date, dueDate: record.dueDate, interval: record.recurrence,
                isLate: isLate(record), seriesCount: group.count
            ))
        }
        for group in collapse(transactions) {
            let record = group.newest
            result.append(ThingLogRow(
                id: record.id, title: record.details, isEvent: false,
                signedAmount: record.kind == .expense ? -record.amount : record.amount,
                payeeContactID: record.payeeContactID,
                date: record.date, dueDate: record.dueDate, interval: record.recurrence,
                isLate: isLate(record), seriesCount: group.count
            ))
        }
        return result.sorted(by: precedes)
    }

    // MARK: - Collapsing

    private struct Group<R: SeriesRecord> {
        let newest: R
        let count: Int
    }

    private static func collapse<R: SeriesRecord>(_ records: [R]) -> [Group<R>] {
        var byGroup: [String: [R]] = [:]
        for record in records {
            byGroup[record.seriesID?.uuidString ?? record.id.uuidString, default: []].append(record)
        }
        return byGroup.values.compactMap { members in
            guard let any = members.first else { return nil }
            return Group(newest: SeriesLogic.newest(of: any, in: members), count: members.count)
        }
    }

    /// Late first — the whole point of the badge is to float to the top. Then recurring before
    /// one-off and newest date first, matching the ordering the section lists already use.
    private static func precedes(_ lhs: ThingLogRow, _ rhs: ThingLogRow) -> Bool {
        if lhs.isLate != rhs.isLate { return lhs.isLate }
        if lhs.recurs != rhs.recurs { return lhs.recurs }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
