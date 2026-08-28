import SwiftUI

// MARK: - View Series

/// One row of a series history — an Event or Transaction reduced to the fields common to both, so
/// one row view renders either. `amountText`/`amountColor` are nil for an event.
struct SeriesOccurrenceDisplay: Identifiable {
    let id: UUID
    let description: String
    let amountText: String?
    let amountColor: Color?
    let date: Date
    let dueDate: Date?
    let intervalAbbreviation: String

    init(event: Event) {
        id = event.id
        description = event.title
        amountText = nil
        amountColor = nil
        date = event.date
        dueDate = event.dueDate
        intervalAbbreviation = event.recurrence?.abbreviation ?? ""
    }

    init(transaction: Transaction) {
        id = transaction.id
        description = transaction.details
        let sign = transaction.kind == .expense ? "-" : "+"
        amountText = "\(sign)\(transaction.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))"
        amountColor = transaction.kind == .expense ? .red : .green
        date = transaction.date
        dueDate = transaction.dueDate
        intervalAbbreviation = transaction.recurrence?.abbreviation ?? ""
    }
}

/// Read-only history of one recurring series, newest occurrence date first — see
/// `LedgerDigest.seriesOccurrences`. Convention-A sheet chrome (plain `NavigationStack { List }`,
/// no themed background) matching the app's other pickers/editors, not the tab-root treatment.
struct SeriesOccurrencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let occurrences: [SeriesOccurrenceDisplay]

    var body: some View {
        NavigationStack {
            List(occurrences) { occurrence in
                SeriesOccurrenceRow(occurrence: occurrence)
            }
            .navigationTitle("Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SeriesOccurrenceRow: View {
    let occurrence: SeriesOccurrenceDisplay

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.description)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(occurrence.date.formatted(date: .abbreviated, time: .omitted))
                    if let dueDate = occurrence.dueDate {
                        Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                    Text(occurrence.intervalAbbreviation)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let amountText = occurrence.amountText {
                Spacer()
                Text(amountText)
                    .fontWeight(.semibold)
                    .foregroundStyle(occurrence.amountColor ?? .primary)
            }
        }
        .padding(.vertical, 2)
    }
}
