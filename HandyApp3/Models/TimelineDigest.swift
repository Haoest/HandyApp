import Foundation

/// One asset's live events/transactions, as input to `TimelineDigest`. Callers must pass
/// `liveEvents`/`liveTransactions` — tombstones are not filtered here.
struct TimelineSource {
    let assetID: UUID
    let assetName: String
    let events: [Event]
    let transactions: [Transaction]
}

/// The relative due windows the Timeline groups watched records into. Ordered as displayed.
enum TimelineWindow: String, CaseIterable {
    case overdue, thisWeek, nextTwoWeeks, laterThisMonth

    /// Upper bound in days-until-due, inclusive. `overdue` is everything below zero.
    var upperBound: Int {
        switch self {
        case .overdue: return -1
        case .thisWeek: return 7
        case .nextTwoWeeks: return 14
        case .laterThisMonth: return TimelineDigest.horizonDays
        }
    }

    static func containing(daysUntilDue days: Int) -> TimelineWindow? {
        switch days {
        case ..<0: return .overdue
        case 0...7: return .thisWeek
        case 8...14: return .nextTwoWeeks
        case 15...TimelineDigest.horizonDays: return .laterThisMonth
        default: return nil
        }
    }
}

/// One "Coming up" row: a watched, due-bearing record collapsed to one entry per series.
struct TimelineItem: Identifiable {
    /// The representative record — the series member whose due date is most urgent.
    let id: UUID
    /// The newest occurrence in the same series, which "Log it"/"Log & edit" acts on. Equal to
    /// `id` for a record with no series. Mirrors the timeline's due-line behavior: the *soonest*
    /// due member decides when the row appears, the *newest* member is what gets duplicated.
    let openRecordID: UUID
    let assetID: UUID
    let assetName: String
    let title: String
    let isEvent: Bool
    /// Signed amount for transactions (negative for an expense), `nil` for events.
    let signedAmount: Decimal?
    let payeeContactID: String?
    let dueDate: Date
    let daysUntilDue: Int
    /// The representative record's "Appears this long before" setting — the lead time that
    /// decides whether this row counts as due soon. Taken from the representative, not the
    /// newest member, because `daysUntilDue` is the representative's too.
    let messageDaysBefore: Int
    let interval: RecurrenceInterval?
    /// Whether duplicating `openRecordID` would extend a series — drives "Log it" vs
    /// "Duplicate it" wording, matching the existing row context menus.
    let isSeriesEligible: Bool

    var isOverdue: Bool { daysUntilDue < 0 }

    /// Inside the record's own lead-in window: from `messageDaysBefore` days out through the
    /// due date itself, inclusive at both ends. The due-date end must stay inclusive — a record
    /// due today is not overdue, so excluding it would leave it counted by neither header stat.
    ///
    /// Note this clamps at `TimelineDigest.horizonDays`: a lead time longer than the horizon
    /// (the slider goes to 60) can't be honored here, because the record is filtered out of the
    /// item pool before it reaches this check. Such a record starts counting once it comes
    /// within the horizon, while its notifications still fire at the full lead time.
    var isDueSoon: Bool { daysUntilDue >= 0 && daysUntilDue <= messageDaysBefore }
}

struct TimelineWindowGroup: Identifiable {
    let window: TimelineWindow
    let items: [TimelineItem]
    var id: TimelineWindow { window }

    /// Signed sum of the money records in this window; zero when the window holds only events.
    var netAmount: Decimal { items.compactMap(\.signedAmount).reduce(0, +) }
    var hasMoney: Bool { items.contains { $0.signedAmount != nil } }
}

/// The three figures in the Timeline header.
struct TimelineSummary: Equatable {
    let overdueCount: Int
    /// Watched records inside their own lead-in window — see `TimelineItem.isDueSoon`.
    let upcomingCount: Int
    /// Signed sum of the money due from today through the 31-day horizon. Deliberately *not*
    /// keyed to `upcomingCount`'s set: the count answers "what wants my attention now", the
    /// net answers "what is scheduled this month", and narrowing the net to the lead-in
    /// window would make it swing as unrelated records enter and leave that window.
    let netAmount: Decimal
}

/// Buckets watched (due-bearing) events and transactions across every asset into the Timeline's
/// relative windows — overdue, this week, next two weeks, later this month.
///
/// Series collapsing matches the timeline's due candidates: one row per series, represented by the
/// member with the soonest due date, acting on the newest member. `SeriesLogic.isSuppressed`
/// still applies, so an occurrence that has already been logged this period drops off.
///
/// **Window semantics differ from the Home tab's due section.** Home gates purely on
/// `SeriesLogic.isDueMessageActive`, so a record with the default 7-day lead simply doesn't
/// appear until a week before it's due — which would leave "Next two weeks" and "Later this
/// month" permanently empty. Here, `messageDaysBefore` does not gate *membership*: everything
/// watched and due inside `horizonDays` is listed. It does decide the header's "Due soon" count
/// (`TimelineItem.isDueSoon`), so the lead-time slider governs which rows the header calls out
/// without emptying the windows below it — meaning the header count is deliberately a subset of
/// the rows on screen, not a total of them. `messageDaysAfter` *is* still honored as the lower
/// bound on `overdue`, so a long-ignored record eventually stops nagging exactly as it does
/// today; the two settings now bound the header's two counts symmetrically, one on each side of
/// the due date.
enum TimelineDigest {
    /// How far ahead the Timeline looks, in days. Records due beyond this appear in neither the
    /// windows nor the header summary — including one whose `messageDaysBefore` reaches further
    /// than the horizon, which therefore starts counting as due soon only once it crosses it.
    static let horizonDays = 31

    static func items(sources: [TimelineSource], calendar: Calendar = .current, now: Date = Date()) -> [TimelineItem] {
        var result: [TimelineItem] = []
        for source in sources {
            result += candidates(in: source.events, calendar: calendar, now: now).map { candidate in
                TimelineItem(
                    id: candidate.representative.id,
                    openRecordID: candidate.newest.id,
                    assetID: source.assetID,
                    assetName: source.assetName,
                    title: candidate.newest.title,
                    isEvent: true,
                    signedAmount: nil,
                    payeeContactID: nil,
                    dueDate: candidate.dueDate,
                    daysUntilDue: candidate.daysUntilDue,
                    messageDaysBefore: candidate.representative.messageDaysBefore,
                    interval: candidate.newest.recurrence,
                    isSeriesEligible: candidate.newest.recurrence != nil
                )
            }
            result += candidates(in: source.transactions, calendar: calendar, now: now).map { candidate in
                let record = candidate.newest
                let signed = record.kind == .expense ? -record.amount : record.amount
                return TimelineItem(
                    id: candidate.representative.id,
                    openRecordID: record.id,
                    assetID: source.assetID,
                    assetName: source.assetName,
                    title: record.details,
                    isEvent: false,
                    signedAmount: signed,
                    payeeContactID: record.payeeContactID,
                    dueDate: candidate.dueDate,
                    daysUntilDue: candidate.daysUntilDue,
                    messageDaysBefore: candidate.representative.messageDaysBefore,
                    interval: record.recurrence,
                    isSeriesEligible: record.recurrence != nil
                )
            }
        }
        return result.sorted(by: precedes)
    }

    static func groups(from items: [TimelineItem]) -> [TimelineWindowGroup] {
        TimelineWindow.allCases.compactMap { window in
            let matching = items.filter { TimelineWindow.containing(daysUntilDue: $0.daysUntilDue) == window }
            guard !matching.isEmpty else { return nil }
            return TimelineWindowGroup(window: window, items: matching)
        }
    }

    static func summary(from items: [TimelineItem]) -> TimelineSummary {
        let scheduled = items.filter { $0.daysUntilDue >= 0 && $0.daysUntilDue <= horizonDays }
        return TimelineSummary(
            overdueCount: items.filter(\.isOverdue).count,
            upcomingCount: items.filter(\.isDueSoon).count,
            netAmount: scheduled.compactMap(\.signedAmount).reduce(0, +)
        )
    }

    // MARK: - Series collapsing

    private struct Candidate<R: SeriesRecord> {
        let representative: R
        let newest: R
        let dueDate: Date
        let daysUntilDue: Int
    }

    /// One candidate per series: the member with the soonest due date that is still inside the
    /// displayed range, paired with the series' newest member. Suppressed members (a newer
    /// sibling already logged this period) are skipped, as are records with no due date.
    private static func candidates<R: SeriesRecord>(in records: [R], calendar: Calendar, now: Date) -> [Candidate<R>] {
        let today = calendar.startOfDay(for: now)
        var bestByGroup: [String: (record: R, dueDate: Date, days: Int)] = [:]

        for record in records {
            guard let dueDate = record.dueDate,
                  !SeriesLogic.isSuppressed(record, in: records, calendar: calendar, now: now),
                  let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: dueDate)).day,
                  days <= horizonDays,
                  // Stale overdue records stop nagging once their post-due window lapses —
                  // the one part of the message-window settings the Timeline still enforces.
                  days >= -record.messageDaysAfter else { continue }

            let key = record.seriesID?.uuidString ?? record.id.uuidString
            if let existing = bestByGroup[key] {
                let better = dueDate < existing.dueDate
                    || (dueDate == existing.dueDate && record.id.uuidString < existing.record.id.uuidString)
                if better { bestByGroup[key] = (record, dueDate, days) }
            } else {
                bestByGroup[key] = (record, dueDate, days)
            }
        }

        return bestByGroup.values.map { entry in
            Candidate(
                representative: entry.record,
                newest: SeriesLogic.newest(of: entry.record, in: records),
                dueDate: entry.dueDate,
                daysUntilDue: entry.days
            )
        }
    }

    /// Soonest due first, with a deterministic id tiebreak so ordering survives a round trip.
    private static func precedes(_ lhs: TimelineItem, _ rhs: TimelineItem) -> Bool {
        if lhs.daysUntilDue != rhs.daysUntilDue { return lhs.daysUntilDue < rhs.daysUntilDue }
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
