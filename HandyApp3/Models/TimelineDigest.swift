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
    /// Signed sum of the money that actually moved in the trailing `horizonDays` — see
    /// `TimelineDigest.cashFlowEntries`. Unlike the two counts beside it this looks *backward*
    /// and ignores due dates entirely, so the header reads as "what needs attention" next to
    /// "what it has been costing".
    let recentCashFlow: Decimal
}

/// One line of the cash-flow peek: a single transaction that landed inside the trailing
/// window, carrying the asset it belongs to. Unlike `TimelineItem` these are never collapsed —
/// each occurrence of a recurring bill is its own entry, because each is its own payment.
struct CashFlowEntry: Identifiable {
    /// The transaction's own id.
    let id: UUID
    let assetID: UUID
    let assetName: String
    let details: String
    /// The transaction's occurrence date. Shown on the row, but not what the list is ordered
    /// by — it only breaks ties between equal amounts.
    let date: Date
    /// Negative for an expense, positive for income.
    let signedAmount: Decimal
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
    /// How far the Timeline looks in days — in *both* directions, so the screen reaches back
    /// exactly as far as it reaches forward.
    ///
    /// Forward it bounds the watched item pool and `TimelineWindow.laterThisMonth`'s upper
    /// bound: records due beyond it appear in neither the windows nor the header summary,
    /// including one whose `messageDaysBefore` reaches further than the horizon, which
    /// therefore starts counting as due soon only once it crosses it. Backward it bounds
    /// `cashFlowEntries`. Moving it moves both halves of the screen at once — that is the
    /// point, but it is why the constant is worth changing deliberately rather than in passing.
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

    /// `sources` is taken alongside `items` rather than re-derived here: the caller already
    /// holds both, and the cash-flow figure deliberately reads the raw records that `items`
    /// has thrown away — see `cashFlowEntries`.
    static func summary(from items: [TimelineItem], sources: [TimelineSource],
                        calendar: Calendar = .current, now: Date = Date()) -> TimelineSummary {
        TimelineSummary(
            overdueCount: items.filter(\.isOverdue).count,
            upcomingCount: items.filter(\.isDueSoon).count,
            recentCashFlow: recentCashFlow(sources: sources, calendar: calendar, now: now)
        )
    }

    /// Signed sum of the money that landed in the trailing window — exactly the sum of
    /// `cashFlowEntries`, so the header figure and the list behind it cannot disagree.
    static func recentCashFlow(sources: [TimelineSource], calendar: Calendar = .current,
                               now: Date = Date()) -> Decimal {
        cashFlowEntries(sources: sources, calendar: calendar, now: now)
            .reduce(into: Decimal(0)) { $0 += $1.signedAmount }
    }

    /// Every live transaction whose *occurrence date* falls in the trailing `horizonDays` —
    /// today plus the `horizonDays` days before it — largest *absolute* amount first, so the
    /// biggest movements lead whichever direction they went, and a big expense is not buried
    /// beneath every scrap of income.
    ///
    /// Deliberately built from the raw records rather than from `items`, because every filter
    /// `items` applies is wrong for this question. Due dates don't enter into it: a bill is
    /// money spent on the day it was paid, whatever day it was owed, and a record with no due
    /// date at all — invisible everywhere else on this screen — still appears here.
    /// `SeriesLogic.isSuppressed` doesn't apply either: suppression is a don't-nag display
    /// rule, and both a logged occurrence and the one that superseded it are real money.
    /// Series are not collapsed, for the same reason.
    ///
    /// Two consequences worth knowing. Future-dated records fall outside the window, so a
    /// transaction entered today but dated next month doesn't count until it arrives. And
    /// because "Log Now" stamps the new occurrence with today's date, a monthly series lands
    /// one or two hits in any one window depending on where its due date sits relative to
    /// today — the figure is honest about what the dates say, but it is not smooth month to
    /// month.
    ///
    /// Callers pass `liveTransactions` off `AssetStore.allAssets`, which is already free of
    /// deleted and purged assets, so no further liveness filtering belongs here.
    static func cashFlowEntries(sources: [TimelineSource], calendar: Calendar = .current,
                                now: Date = Date()) -> [CashFlowEntry] {
        let today = calendar.startOfDay(for: now)
        var result: [(entry: CashFlowEntry, createdAt: TimeInterval)] = []

        for source in sources {
            for transaction in source.transactions {
                guard let daysAgo = calendar.dateComponents([.day],
                                                            from: calendar.startOfDay(for: transaction.date),
                                                            to: today).day,
                      daysAgo >= 0, daysAgo <= horizonDays else { continue }
                let entry = CashFlowEntry(
                    id: transaction.id,
                    assetID: source.assetID,
                    assetName: source.assetName,
                    details: transaction.details,
                    date: transaction.date,
                    signedAmount: transaction.kind == .expense ? -transaction.amount : transaction.amount
                )
                result.append((entry, transaction.createdAt.timeIntervalSince1970.rounded(.down)))
            }
        }

        // Magnitude descending, direction ignored: the largest movements lead. Ties then break
        // on the signed amount, so an equal-sized income and expense are ordered income first
        // rather than arbitrarily; then newest occurrence first — routine for a recurring bill
        // appearing twice in one window, whose two rows are necessarily adjacent here; then
        // `createdAt` truncated to whole seconds, then `id`. That tail is
        // `LedgerDigest.seriesByOccurrenceDate`'s rule, which keeps the order stable across a
        // persistence round trip (ISO-8601 carries no sub-second precision).
        return result.sorted { lhs, rhs in
            let (l, r) = (abs(lhs.entry.signedAmount), abs(rhs.entry.signedAmount))
            if l != r { return l > r }
            if lhs.entry.signedAmount != rhs.entry.signedAmount {
                return lhs.entry.signedAmount > rhs.entry.signedAmount
            }
            if lhs.entry.date != rhs.entry.date { return lhs.entry.date > rhs.entry.date }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.entry.id.uuidString < rhs.entry.id.uuidString
        }.map(\.entry)
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
