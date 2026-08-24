import Foundation

/// `SeriesRecord` plus the record's own occurrence date — the extra bit `LedgerDigest` needs
/// that `DueSeries.swift`'s series/due-window logic doesn't.
protocol LedgerRecord: SeriesRecord {
    var date: Date { get }
}

extension Event: LedgerRecord {}
extension Transaction: LedgerRecord {}

/// Which record types to include. Independent of, and combinable with, the "late only" toggle
/// — e.g. `.eventsOnly` + late-only shows only late events, not late events and transactions.
enum LedgerTypeFilter: String, CaseIterable {
    case all, eventsOnly, transactionsOnly
}

struct LedgerRecurringFacts: Equatable {
    let interval: RecurrenceInterval
    let nextExpected: Date
    let isLate: Bool
}

/// One row of the Logs tab — an Event or Transaction paired with its
/// recurring facts (nil for a non-recurring record).
enum LedgerEntry: Identifiable {
    case event(Event, LedgerRecurringFacts?)
    case transaction(Transaction, LedgerRecurringFacts?)

    var id: String {
        switch self {
        case .event(let event, _): return "event-\(event.id.uuidString)"
        case .transaction(let transaction, _): return "transaction-\(transaction.id.uuidString)"
        }
    }

    var recordID: UUID {
        switch self {
        case .event(let event, _): return event.id
        case .transaction(let transaction, _): return transaction.id
        }
    }

    var date: Date {
        switch self {
        case .event(let event, _): return event.date
        case .transaction(let transaction, _): return transaction.date
        }
    }

    var facts: LedgerRecurringFacts? {
        switch self {
        case .event(_, let facts), .transaction(_, let facts): return facts
        }
    }
}

/// One asset's live events/transactions, as input to `LedgerDigest.build`. Callers must pass
/// `liveEvents`/`liveTransactions` — tombstones are not filtered here.
struct LedgerSource {
    let assetID: UUID
    let assetName: String
    let events: [Event]
    let transactions: [Transaction]
}

struct LedgerAssetGroup: Identifiable {
    let assetID: UUID
    let assetName: String
    let entries: [LedgerEntry]
    let newestDate: Date
    var id: UUID { assetID }
}

/// Aggregates events/transactions across every asset for the Logs tab: a
/// recent-activity window for non-recurring records, the newest logged occurrence of each
/// recurring series regardless of age, grouped by asset and sorted for display. Modeled on
/// `HomeActivityDigest`/`SeriesLogic` — pure, `Calendar`/`now` injected, deterministic tiebreaks.
enum LedgerDigest {
    static let defaultWindowMonths = 6

    static func build(sources: [LedgerSource], typeFilter: LedgerTypeFilter = .all, lateOnly: Bool = false, windowMonths: Int = defaultWindowMonths, calendar: Calendar = .current, now: Date = Date()) -> [LedgerAssetGroup] {
        sources.compactMap { source in
            let events = select(source.events, windowMonths: windowMonths, calendar: calendar, now: now)
            let transactions = select(source.transactions, windowMonths: windowMonths, calendar: calendar, now: now)

            var entries: [LedgerEntry] = []
            entries += events.recurring.map { LedgerEntry.event($0.record, $0.facts) }
            entries += events.nonRecurring.map { LedgerEntry.event($0, nil) }
            entries += transactions.recurring.map { LedgerEntry.transaction($0.record, $0.facts) }
            entries += transactions.nonRecurring.map { LedgerEntry.transaction($0, nil) }

            var filtered = filterByType(entries, typeFilter: typeFilter)
            if lateOnly { filtered = filtered.filter { $0.facts?.isLate == true } }
            guard !filtered.isEmpty else { return nil }

            let sorted = filtered.sorted(by: precedes)
            let newestDate = sorted.map(\.date).max() ?? .distantPast
            return LedgerAssetGroup(assetID: source.assetID, assetName: source.assetName, entries: sorted, newestDate: newestDate)
        }
        .sorted(by: groupPrecedes)
    }

    /// Partitions `records` into the recurring series picks (newest live occurrence per
    /// series, included regardless of age) and the non-recurring records inside the trailing
    /// `windowMonths`. A series with mixed recurring/non-recurring members (a manually-edited
    /// occurrence) is not treated as one unit here: only its recurring members compete for the
    /// series pick, and any non-recurring member is windowed individually like any other
    /// non-recurring record.
    static func select<R: LedgerRecord>(_ records: [R], windowMonths: Int, calendar: Calendar = .current, now: Date = Date()) -> (recurring: [(record: R, facts: LedgerRecurringFacts)], nonRecurring: [R]) {
        let recurringRecords = records.filter { $0.recurrence != nil }
        let nonRecurringRecords = records.filter { $0.recurrence == nil }

        let cutoff = calendar.date(byAdding: .month, value: -windowMonths, to: calendar.startOfDay(for: now)) ?? .distantPast
        let includedNonRecurring = nonRecurringRecords.filter { $0.date >= cutoff }

        var seenKeys = Set<String>()
        var picked: [(record: R, facts: LedgerRecurringFacts)] = []
        for record in recurringRecords {
            let key = record.seriesID?.uuidString ?? record.id.uuidString
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            let newest = SeriesLogic.newest(of: record, in: recurringRecords)
            guard let facts = recurringFacts(for: newest, calendar: calendar, now: now) else { continue }
            picked.append((newest, facts))
        }
        return (picked, includedNonRecurring)
    }

    /// Next occurrence = `dueDate` rolled forward in whole intervals until it clears the
    /// record's own date — the same projection `SeriesLogic.projectedDueDate` writes when an
    /// occurrence is logged, re-applied at read time.
    ///
    /// Rolling here rather than trusting `dueDate` outright repairs a *stale* due date in the
    /// display: editing a record's date forward without touching its due date (anything other
    /// than Log Now) otherwise reads as "next occurrence" in the past — a quarterly item dated
    /// Aug 23 still carrying its Jun 1 due date shows Sep 1, not Jun 1. And rolling only past
    /// the record's own date — never past `now` — leaves a genuinely overdue series overdue, so
    /// `isLate` still fires.
    ///
    /// A record whose due date is already correct is untouched by this: an occurrence logged
    /// Aug 23 carrying its freshly projected Sep 1 due date shows Sep 1, not one interval more.
    /// Falls back to `date` when no due date has ever been set, which the same roll then
    /// advances by exactly one interval.
    static func recurringFacts<R: LedgerRecord>(for record: R, calendar: Calendar = .current, now: Date = Date()) -> LedgerRecurringFacts? {
        guard let interval = record.recurrence else { return nil }
        let base = record.dueDate ?? record.date
        let nextExpected = SeriesLogic.rollForward(base, past: record.date, interval: interval, calendar: calendar)
        let isLate = calendar.startOfDay(for: now) > calendar.startOfDay(for: nextExpected)
        return LedgerRecurringFacts(interval: interval, nextExpected: nextExpected, isLate: isLate)
    }

    private static func filterByType(_ entries: [LedgerEntry], typeFilter: LedgerTypeFilter) -> [LedgerEntry] {
        switch typeFilter {
        case .all: return entries
        case .eventsOnly: return entries.filter { if case .event = $0 { return true }; return false }
        case .transactionsOnly: return entries.filter { if case .transaction = $0 { return true }; return false }
        }
    }

    /// Recurring first (interval shortest-first — `RecurrenceInterval.allCases` is already
    /// ordered shortest to longest), then date descending; non-recurring after, date
    /// descending; deterministic id tiebreak throughout.
    private static func precedes(_ lhs: LedgerEntry, _ rhs: LedgerEntry) -> Bool {
        let lRank = lhs.facts.map { intervalRank($0.interval) }
        let rRank = rhs.facts.map { intervalRank($0.interval) }
        if (lRank != nil) != (rRank != nil) { return lRank != nil }
        if let lRank, let rRank, lRank != rRank { return lRank < rRank }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id < rhs.id
    }

    private static func intervalRank(_ interval: RecurrenceInterval) -> Int {
        RecurrenceInterval.allCases.firstIndex(of: interval) ?? RecurrenceInterval.allCases.count
    }

    private static func groupPrecedes(_ lhs: LedgerAssetGroup, _ rhs: LedgerAssetGroup) -> Bool {
        if lhs.newestDate != rhs.newestDate { return lhs.newestDate > rhs.newestDate }
        let nameOrder = lhs.assetName.localizedCompare(rhs.assetName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.assetID.uuidString < rhs.assetID.uuidString
    }
}
