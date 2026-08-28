import Foundation

/// The at-a-glance figures a Things row shows under an asset's name.
struct ThingFacts: Equatable {
    /// Soonest upcoming due date across the asset's watched records, or the soonest *overdue*
    /// one when something is late. Deliberately **not** bounded by `TimelineDigest.horizonDays`:
    /// the Timeline only looks a month ahead, but a Things row shows a next date however far out
    /// it is — an annual service due in eight months still reads better than "—".
    let nextDue: Date?
    /// True when a watched record is past due and still inside its post-due message window,
    /// matching the Timeline's `overdue` bucket so the two screens never disagree about "late".
    let isLate: Bool
    /// Live events plus live transactions.
    let recordCount: Int
    /// Signed sum of the transactions *dated* in the trailing 12 months — actual spend, not
    /// what is scheduled. Negative when the asset costs more than it returns.
    let netLast12Months: Decimal
}

/// Per-asset roll-ups for the Things list. Pure and `Calendar`/`now`-injected, in the same
/// shape as `TimelineDigest`, so the row figures are unit-testable without a store.
enum ThingsDigest {

    static func facts<E: SeriesRecord, T: SeriesRecord>(
        events: [E], transactions: [T], transactionAmounts: [(date: Date, signedAmount: Decimal)],
        calendar: Calendar = .current, now: Date = Date()
    ) -> ThingFacts {
        let today = calendar.startOfDay(for: now)
        var upcoming: [Date] = []
        var overdue: [Date] = []

        func collect<R: SeriesRecord>(_ records: [R]) {
            for record in records {
                guard let dueDate = record.dueDate,
                      !SeriesLogic.isSuppressed(record, in: records, calendar: calendar, now: now),
                      let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: dueDate)).day
                else { continue }
                if days >= 0 {
                    upcoming.append(dueDate)
                } else if days >= -record.messageDaysAfter {
                    // Same lower bound the Timeline applies: a long-ignored record stops
                    // counting as late rather than flagging the thing forever.
                    overdue.append(dueDate)
                }
            }
        }
        collect(events)
        collect(transactions)

        let cutoff = calendar.date(byAdding: .month, value: -12, to: today) ?? .distantPast
        let net = transactionAmounts
            .filter { $0.date >= cutoff }
            .reduce(Decimal(0)) { $0 + $1.signedAmount }

        return ThingFacts(
            // An overdue record outranks an upcoming one — the row's "Next" should name the
            // thing that needs attention now, not the next one on the calendar.
            nextDue: overdue.min() ?? upcoming.min(),
            isLate: !overdue.isEmpty,
            recordCount: events.count + transactions.count,
            netLast12Months: net
        )
    }

    /// The one-line spec under a thing's name: the first few filled-in property values, joined
    /// with a middot — "Ferrari · Testarossa · 1985". Contact and binary values are skipped;
    /// neither reads as a spec.
    static func spec(from values: [StoredValue], limit: Int = 3) -> String {
        values
            .compactMap { value -> String? in
                switch value {
                case .contact, .data: return nil
                default:
                    let text = value.shortDisplay.trimmingCharacters(in: .whitespaces)
                    return text.isEmpty ? nil : text
                }
            }
            .prefix(limit)
            .joined(separator: " · ")
    }
}
