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
    let onAdd: () -> Void
    /// Called when a creation action is blocked by the free-tier transaction limit.
    /// The paywall itself is presented by the owner (see AssetDetailView's
    /// note on why sheets can't live at the section/row level).
    let onLimitReached: () -> Void

    /// Non-recurring items shown inline before collapsing behind the "Show All"
    /// row; recurring items are never collapsed. Fixed at `AppPreference.nonRecurringLimitDefault`
    /// (the Preferences screen that used to tune this was removed).
    @AppStorage(AppPreference.transactionLimitKey)
    private var nonRecurringLimit = AppPreference.nonRecurringLimitDefault

    private var sorted: [Transaction] { asset.liveTransactions.recurringFirstDateDescending() }

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
        Section {
            if sorted.isEmpty {
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
        } header: {
            AddSectionHeader(title: "Transactions", action: onAdd)
        }
    }
}

struct TransactionListView: View {
    let asset: Asset
    @Binding var sheetMode: TransactionSheetMode?
    let onLimitReached: () -> Void

    private var sorted: [Transaction] { asset.liveTransactions.recurringFirstDateDescending() }

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

    /// Recurring transactions join (or start) a series when duplicated — "Log" wording signals
    /// that, versus a plain "Duplicate" for a one-off copy.
    private var quickActionTitle: LocalizedStringKey { transaction.recurrence != nil ? "Log Now" : "Duplicate" }
    private var reviewActionTitle: LocalizedStringKey { transaction.recurrence != nil ? "Log & Edit" : "Duplicate & Edit" }

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
                        try? store.duplicateTransaction(id: transaction.id, onAssetID: asset.id)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label(quickActionTitle, systemImage: "plus.square.on.square")
                }
                Button {
                    if store.hasTransactionCapacity(for: asset) {
                        sheetMode = .duplicate(transaction)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label(reviewActionTitle, systemImage: "square.and.pencil")
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
    @Environment(AssetStore.self) private var store
    let existing: Transaction?
    let seriesCount: Int
    /// Asset name and ID, used only by the debug "send test notification" button to
    /// mirror the real notification's title and tap-routing target.
    let assetName: String
    let assetID: UUID
    let onSave: (String, Decimal, Date, TransactionKind, String?, String, RecurrenceInterval?, DueSettings) -> Void

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
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var messageDaysBefore: Int
    @State private var messageDaysAfter: Int
    @State private var deviceNotificationOn: Bool
    @State private var deviceNotificationDaysBefore: Int

    init(existing: Transaction? = nil, prefill: Transaction? = nil, prefillDetails: String? = nil, prefillDue: DueSettings? = nil,
         initialKind: TransactionKind? = nil, seriesCount: Int = 1, assetName: String, assetID: UUID,
         onSave: @escaping (String, Decimal, Date, TransactionKind, String?, String, RecurrenceInterval?, DueSettings) -> Void) {
        self.existing = existing
        self.seriesCount = seriesCount
        self.assetName = assetName
        self.assetID = assetID
        self.onSave = onSave
        let source = existing ?? prefill
        _details = State(initialValue: prefillDetails ?? source?.details ?? "")
        _amountText = State(initialValue: source.map { "\($0.amount)" } ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _kind = State(initialValue: source?.kind ?? initialKind ?? .expense)
        _payeeContactID = State(initialValue: source?.payeeContactID)
        _notes = State(initialValue: source?.notes ?? "")
        // A series duplicate inherits recurrence from its source so the chain of occurrences
        // keeps repeating; NotificationPlanner schedules reminders from only the newest
        // occurrence of a series so this can't double them up.
        _isRecurring = State(initialValue: source?.recurrence != nil)
        _interval = State(initialValue: source?.recurrence ?? .monthly)
        let resolvedName: String
        if let id = source?.payeeContactID {
            resolvedName = ContactResolver.shared.displayName(for: id) ?? ""
        } else {
            resolvedName = ""
        }
        _payeeName = State(initialValue: resolvedName)
        let due = existing.map {
            DueSettings(dueDate: $0.dueDate, messageDaysBefore: $0.messageDaysBefore, messageDaysAfter: $0.messageDaysAfter,
                       deviceNotificationOn: $0.deviceNotificationOn, deviceNotificationDaysBefore: $0.deviceNotificationDaysBefore)
        } ?? prefillDue ?? DueSettings()
        _hasDueDate = State(initialValue: due.dueDate != nil)
        _dueDate = State(initialValue: due.dueDate ?? Date())
        _messageDaysBefore = State(initialValue: due.messageDaysBefore)
        _messageDaysAfter = State(initialValue: due.messageDaysAfter)
        _deviceNotificationOn = State(initialValue: due.deviceNotificationOn)
        _deviceNotificationDaysBefore = State(initialValue: due.deviceNotificationDaysBefore)
    }

    private var parsedAmount: Decimal? { Decimal(string: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("Description", text: $details)
                        .limitLength(TextLimits.transactionDetails, text: $details)
                    if seriesCount > 1 {
                        Text("This series has ^[\(seriesCount) transaction](inflect: true)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
                Section("Date of Transaction") {
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
                Section("Due Date") {
                    Toggle("Has Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .labelsHidden()
                        StepSlider(title: "Show message before due date", value: $messageDaysBefore)
                        StepSlider(title: "Keep message after due date", value: $messageDaysAfter)
                        Toggle("Device Notification", isOn: $deviceNotificationOn)
                        if deviceNotificationOn {
                            StepSlider(title: "Notify before due date", value: $deviceNotificationDaysBefore)
                            #if DEBUG
                            Button("Send Test Notification Now") {
                                let body = NotificationPlanner.transactionDueBody(kind: kind, amount: parsedAmount ?? 0, notes: notes, daysBefore: deviceNotificationDaysBefore)
                                store.notificationScheduler?.fireDebugNotification(
                                    title: assetName, body: body,
                                    assetID: assetID, kind: .transaction
                                )
                            }
                            #endif
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                        .limitLength(TextLimits.transactionNotes, text: $notes)
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
                        let due = DueSettings(dueDate: hasDueDate ? dueDate : nil, messageDaysBefore: messageDaysBefore,
                                              messageDaysAfter: messageDaysAfter, deviceNotificationOn: deviceNotificationOn,
                                              deviceNotificationDaysBefore: deviceNotificationDaysBefore)
                        onSave(details.trimmingCharacters(in: .whitespaces), amount, date, kind, payeeContactID, notes.trimmingCharacters(in: .whitespaces), isRecurring ? interval : nil, due)
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
