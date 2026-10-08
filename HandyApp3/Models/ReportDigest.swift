import Foundation

/// One Thing's live records as input to a report. Callers pass `liveTransactions` and `liveEvents` from
/// live Things; this layer deliberately knows nothing about tombstones or view state.
struct ReportSource {
    let thingID: UUID
    let thingName: String
    let transactions: [Transaction]
    var events: [Event] = []
}

enum ReportDirection: String, CaseIterable, Identifiable {
    case all
    case income
    case expense
    case event

    var id: Self { self }

    func includes(_ kind: TransactionKind) -> Bool {
        switch self {
        case .all: return true
        case .income: return kind == .income
        case .expense: return kind == .expense
        case .event: return false
        }
    }
}

struct ReportEntry: Identifiable, Equatable {
    let id: UUID
    let thingID: UUID
    let thingName: String
    let details: String
    let date: Date
    /// `nil` identifies an event, which has no monetary amount.
    let kind: TransactionKind?
    let amount: Decimal

    var isEvent: Bool { kind == nil }
    var signedAmount: Decimal { kind == .expense ? -amount : amount }
}

struct ReportResult: Equatable {
    let entries: [ReportEntry]
    let moneyIn: Decimal
    let moneyOut: Decimal

    var grandTotal: Decimal { moneyIn - moneyOut }
}

enum ReportDigest {
    /// Builds a report over occurrence dates. Both visible date boundaries are inclusive;
    /// internally the end is represented as the start of the following day so records retain
    /// their time-of-day semantics through daylight-saving transitions.
    static func build(
        sources: [ReportSource],
        startDate: Date,
        endDate: Date,
        selectedThingIDs: Set<UUID>?,
        direction: ReportDirection,
        calendar: Calendar = .current
    ) -> ReportResult {
        let lowerBound = calendar.startOfDay(for: min(startDate, endDate))
        let visibleEnd = calendar.startOfDay(for: max(startDate, endDate))
        let upperBound = calendar.date(byAdding: .day, value: 1, to: visibleEnd) ?? visibleEnd

        var rows: [(entry: ReportEntry, createdAt: TimeInterval)] = []
        var moneyIn: Decimal = 0
        var moneyOut: Decimal = 0

        for source in sources {
            if let selectedThingIDs, !selectedThingIDs.contains(source.thingID) { continue }
            if direction == .all || direction == .event {
                for event in source.events {
                    guard event.date >= lowerBound, event.date < upperBound else { continue }
                    let entry = ReportEntry(
                        id: event.id, thingID: source.thingID, thingName: source.thingName,
                        details: event.title, date: event.date, kind: nil, amount: 0
                    )
                    rows.append((entry, event.createdAt.timeIntervalSince1970.rounded(.down)))
                }
            }
            for transaction in source.transactions {
                guard transaction.date >= lowerBound,
                      transaction.date < upperBound,
                      direction.includes(transaction.kind) else { continue }

                let entry = ReportEntry(
                    id: transaction.id,
                    thingID: source.thingID,
                    thingName: source.thingName,
                    details: transaction.details,
                    date: transaction.date,
                    kind: transaction.kind,
                    amount: transaction.amount
                )
                rows.append((entry, transaction.createdAt.timeIntervalSince1970.rounded(.down)))
                if transaction.kind == .income {
                    moneyIn += transaction.amount
                } else {
                    moneyOut += transaction.amount
                }
            }
        }

        let entries = rows.sorted { lhs, rhs in
            if lhs.entry.date != rhs.entry.date { return lhs.entry.date > rhs.entry.date }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.entry.id.uuidString < rhs.entry.id.uuidString
        }.map(\.entry)

        return ReportResult(entries: entries, moneyIn: moneyIn, moneyOut: moneyOut)
    }
}
