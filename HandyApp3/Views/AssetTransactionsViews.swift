import SwiftUI

// MARK: - Recurring-first ordering

private extension Array where Element == Transaction {
    func recurringFirstDateDescending() -> [Transaction] {
        sorted {
            if ($0.recurrence != nil) != ($1.recurrence != nil) { return $0.recurrence != nil }
            return $0.date > $1.date
        }
    }
}

// MARK: - Transactions section

enum TransactionSheetMode: Identifiable {
    case edit(Transaction)
    case duplicate(Transaction)

    var id: UUID {
        switch self {
        case .edit(let txn), .duplicate(let txn): txn.id
        }
    }
}

struct TransactionsSection: View {
    let asset: Asset
    @Binding var sheetMode: TransactionSheetMode?
    /// Called when a creation action is blocked by the free-tier transaction limit.
    /// The paywall itself is presented by the owner (see AssetDetailView's
    /// note on why sheets can't live at the section/row level).
    let onLimitReached: () -> Void

    /// Non-recurring items shown inline before collapsing behind the "Show All"
    /// row; recurring items are never collapsed. User-tunable in Preferences.
    @AppStorage(AppPreference.transactionLimitKey)
    private var nonRecurringLimit = AppPreference.nonRecurringLimitDefault

    private var sorted: [Transaction] { asset.transactions.recurringFirstDateDescending() }

    private var displayed: [Transaction] {
        var remaining = nonRecurringLimit
        return sorted.filter { txn in
            guard txn.recurrence == nil else { return true }
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
    }

    private var hasMore: Bool {
        sorted.filter { $0.recurrence == nil }.count > nonRecurringLimit
    }

    var body: some View {
        Section("Transactions") {
            if asset.transactions.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(displayed) { txn in
                    TransactionItemRow(asset: asset, transaction: txn, sheetMode: $sheetMode, onLimitReached: onLimitReached)
                        .pagingExcludedRow(id: txn.id.uuidString)
                }
                if hasMore {
                    NavigationLink {
                        TransactionListView(asset: asset, sheetMode: $sheetMode, onLimitReached: onLimitReached)
                    } label: {
                        Text("Show All").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct TransactionListView: View {
    let asset: Asset
    @Binding var sheetMode: TransactionSheetMode?
    let onLimitReached: () -> Void

    private var sorted: [Transaction] { asset.transactions.recurringFirstDateDescending() }

    var body: some View {
        List {
            ForEach(sorted) { txn in
                TransactionItemRow(asset: asset, transaction: txn, sheetMode: $sheetMode, onLimitReached: onLimitReached)
            }
        }
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TransactionItemRow: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    let transaction: Transaction
    @Binding var sheetMode: TransactionSheetMode?
    let onLimitReached: () -> Void

    var body: some View {
        TransactionRow(transaction: transaction)
            .contentShape(Rectangle())
            .onTapGesture { sheetMode = .edit(transaction) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    try? store.removeTransaction(id: transaction.id, fromAssetID: asset.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    if store.hasTransactionCapacity(for: asset) {
                        try? store.addTransaction(details: transaction.details, amount: transaction.amount, date: Date(), kind: transaction.kind, payeeContactID: transaction.payeeContactID, notes: transaction.notes, toAssetID: asset.id)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    if store.hasTransactionCapacity(for: asset) {
                        sheetMode = .duplicate(transaction)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label("Duplicate…", systemImage: "square.and.pencil")
                }
            }
    }
}

private struct TransactionRow: View {
    let transaction: Transaction

    private var amountText: String {
        let sign = transaction.kind == .expense ? "-" : "+"
        let formatted = transaction.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        return "\(sign)\(formatted)"
    }

    private var amountColor: Color {
        transaction.kind == .expense ? .red : .green
    }

    private var payeeName: String? {
        guard let id = transaction.payeeContactID else { return nil }
        return ContactResolver.shared.displayName(for: id)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.details)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let name = payeeName {
                        Text("· \(name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let recurrence = transaction.recurrence {
                        Label(recurrence.rawValue, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !transaction.notes.isEmpty {
                    Text(transaction.notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(amountText)
                .fontWeight(.semibold)
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Transaction edit sheet

struct TransactionEditView: View {
    @Environment(\.dismiss) private var dismiss
    let existing: Transaction?
    let onSave: (String, Decimal, Date, TransactionKind, String?, String, RecurrenceInterval?) -> Void

    @State private var details: String
    @State private var amountText: String
    @State private var date: Date
    @State private var kind: TransactionKind
    @State private var payeeContactID: String?
    @State private var payeeName: String
    @State private var notes: String
    @State private var isRecurring: Bool
    @State private var interval: RecurrenceInterval
    @State private var contactPickerPresented = false

    init(existing: Transaction? = nil, prefill: Transaction? = nil, onSave: @escaping (String, Decimal, Date, TransactionKind, String?, String, RecurrenceInterval?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        let source = existing ?? prefill
        _details = State(initialValue: source?.details ?? "")
        _amountText = State(initialValue: source.map { "\($0.amount)" } ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _kind = State(initialValue: source?.kind ?? .expense)
        _payeeContactID = State(initialValue: source?.payeeContactID)
        _notes = State(initialValue: source?.notes ?? "")
        // Recurrence intentionally doesn't carry over from a duplicate prefill —
        // a copy starts non-recurring so duplication can't silently double reminders.
        _isRecurring = State(initialValue: existing?.recurrence != nil)
        _interval = State(initialValue: existing?.recurrence ?? .monthly)
        let resolvedName: String
        if let id = source?.payeeContactID {
            resolvedName = ContactResolver.shared.displayName(for: id) ?? ""
        } else {
            resolvedName = ""
        }
        _payeeName = State(initialValue: resolvedName)
    }

    private var parsedAmount: Decimal? { Decimal(string: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("Description", text: $details)
                }
                Section("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Type", selection: $kind) {
                        ForEach(TransactionKind.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                Section("Recurrence") {
                    Toggle("Recurring", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Repeats", selection: $interval) {
                            ForEach(RecurrenceInterval.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                Section("Contact") {
                    if payeeContactID != nil {
                        HStack {
                            Text(payeeName.isEmpty ? "(not found)" : payeeName)
                                .foregroundStyle(payeeName.isEmpty ? .tertiary : .primary)
                            Spacer()
                            Button { contactPickerPresented = true } label: {
                                Image(systemName: "person.crop.circle")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                payeeContactID = nil
                                payeeName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Button { contactPickerPresented = true } label: {
                            Label("Choose Contact", systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let amount = parsedAmount ?? 0
                        onSave(details.trimmingCharacters(in: .whitespaces), amount, date, kind, payeeContactID, notes.trimmingCharacters(in: .whitespaces), isRecurring ? interval : nil)
                        dismiss()
                    }
                    .disabled(details.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount == nil)
                }
            }
            .background(
                ContactPicker(isPresented: $contactPickerPresented) { id, name in
                    payeeContactID = id
                    payeeName = name
                }
            )
        }
    }
}
