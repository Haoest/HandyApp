import SwiftUI

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

// MARK: - Transaction edit sheet

struct TransactionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AssetStore.self) private var store
    let existing: Transaction?
    /// Series source this sheet is logging a new occurrence from ("Log & Edit"), used to
    /// re-project the due date as the occurrence date changes. Nil for plain add/edit.
    let prefill: Transaction?
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
    /// True while the due date is still derived from the series rather than typed by the user.
    /// Set only for "Log & Edit" on a recurring source that has a due date to project from, and
    /// cleared for good the first time the user edits the field. Deliberately per-sheet-instance
    /// state, not persisted: cancelling and reopening starts the projection fresh.
    @State private var dueDateAutoManaged: Bool
    /// Same idea as `dueDateAutoManaged`, for the details field. Set only for "Log & Edit" on a
    /// recurring source.
    @State private var detailsAutoManaged: Bool
    /// The last value this sheet itself wrote into `details` — lets `.onChange(of: details)`
    /// tell "the projection just updated this" from "the user typed something" without a
    /// custom `Binding` (which `.limitLength`'s truncation write-back would attribute to the
    /// wrong side; see its doc comment).
    @State private var lastAutoDetails: String

    init(existing: Transaction? = nil, prefill: Transaction? = nil, prefillDetails: String? = nil, prefillDue: DueSettings? = nil,
         initialKind: TransactionKind? = nil, seriesCount: Int = 1, assetName: String, assetID: UUID,
         onSave: @escaping (String, Decimal, Date, TransactionKind, String?, String, RecurrenceInterval?, DueSettings) -> Void) {
        self.existing = existing
        self.prefill = prefill
        self.seriesCount = seriesCount
        self.assetName = assetName
        self.assetID = assetID
        self.onSave = onSave
        let source = existing ?? prefill
        let initialDetails = prefillDetails ?? source?.details ?? ""
        _details = State(initialValue: initialDetails)
        _lastAutoDetails = State(initialValue: initialDetails)
        _detailsAutoManaged = State(initialValue: existing == nil && prefill?.recurrence != nil)
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
        _dueDateAutoManaged = State(initialValue: existing == nil && prefill?.recurrence != nil && due.dueDate != nil)
    }

    private var parsedAmount: Decimal? { NumberParsing.decimal(amountText) }

    /// Whether the due date is currently being kept in step with the transaction date. Toggling
    /// recurrence off stops the projection without discarding the flag, so turning it back on
    /// resumes where it left off.
    private var projectsDueDate: Bool { dueDateAutoManaged && isRecurring }

    /// Writes from the date picker mark the field as user-owned; the projection assigns
    /// `dueDate` directly and so leaves the flag alone.
    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { dueDate },
            set: { newValue in
                dueDate = newValue
                dueDateAutoManaged = false
            }
        )
    }

    /// Re-anchors the due date on the series whenever the transaction date — or the interval the
    /// projection walks by — changes, until the user takes the field over.
    private func projectDueDate() {
        guard projectsDueDate, let source = prefill else { return }
        let siblings = store.assets[assetID]?.liveTransactions ?? []
        guard let projected = SeriesLogic.projectedDueDate(for: source, in: siblings, occurrenceDate: date, interval: interval) else { return }
        dueDate = projected
    }

    private var projectsDetails: Bool { detailsAutoManaged && isRecurring }

    /// Re-derives the description from the series' `yyyy-MM` stamping rule
    /// (`suggestedDuplicateTitle` → `SeriesLogic.duplicateTitle`) whenever the transaction date
    /// changes, until the user takes the field over. Writes `lastAutoDetails` before `details`
    /// so the resulting `.onChange(of: details)` sees its own write and leaves the flag alone.
    private func projectDetails() {
        guard projectsDetails, let source = prefill else { return }
        let projected = TextLimits.clamp(store.suggestedDuplicateTitle(forTransactionID: source.id, onAssetID: assetID, at: date), to: TextLimits.transactionDetails)
        lastAutoDetails = projected
        details = projected
    }

    var body: some View {
        RecordSheetScaffold(
            title: existing == nil ? "New transaction" : "Edit transaction",
            saveLabel: "Save",
            canSave: !details.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil,
            onSave: save
        ) {
            RecordField(label: "What happened") {
                TextField("Rent, repair, insurance…", text: $details)
                    .limitLength(TextLimits.transactionDetails, text: $details)
                    .recordInput()
            }
            amountCard
            RecordDateField(label: "Date", date: $date)
            recurrenceCard
            watchCard
            payeeCard
            RecordField(label: "Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
                    .lineLimit(3...)
                    .limitLength(TextLimits.transactionNotes, text: $notes)
                    .recordInput()
            }
            if seriesCount > 1 {
                Text("This series has ^[\(seriesCount) record](inflect: true).")
                    .font(Baron.body(12.5))
                    .foregroundStyle(Baron.neutral600)
            }
        }
        .onChange(of: date) { _, _ in
            projectDueDate()
            projectDetails()
        }
        .onChange(of: interval) { _, _ in projectDueDate() }
        .onChange(of: details) { _, newValue in
            guard detailsAutoManaged, newValue != lastAutoDetails else { return }
            detailsAutoManaged = false
        }
        .background(
            ContactPicker(isPresented: $contactPickerPresented) { id, name in
                payeeContactID = id
                payeeName = name
            }
        )
    }

    private func save() {
        let amount = parsedAmount ?? 0
        let due = DueSettings(dueDate: hasDueDate ? dueDate : nil, messageDaysBefore: messageDaysBefore,
                              messageDaysAfter: messageDaysAfter, deviceNotificationOn: deviceNotificationOn,
                              deviceNotificationDaysBefore: deviceNotificationDaysBefore)
        onSave(details.trimmingCharacters(in: .whitespaces), amount, date, kind, payeeContactID,
               notes.trimmingCharacters(in: .whitespaces), isRecurring ? interval : nil, due)
    }

    /// Amount reads as one large signed figure with the direction chosen beneath it, rather
    /// than a plain number plus a separate "Expense/Income" picker — money out and money in are
    /// the same field seen from two sides, and the sign should be visible while typing.
    private var amountCard: some View {
        let tint = kind == .expense ? Baron.danger : Baron.good
        return VStack(spacing: 13) {
            HStack(spacing: 9) {
                Text(verbatim: kind == .expense ? "−" : "+")
                    .font(Baron.heading(29))
                    .foregroundStyle(tint)
                TextField(String("0.00"), text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(Baron.heading(29))
                    .foregroundStyle(tint)
            }
            HStack(spacing: 8) {
                directionButton("Money out", active: kind == .expense,
                                activeBackground: Baron.dangerBackground, activeForeground: Baron.danger) {
                    kind = .expense
                }
                directionButton("Money in", active: kind == .income,
                                activeBackground: Baron.goodBackground, activeForeground: Baron.good) {
                    kind = .income
                }
            }
        }
        .padding(15)
        .baronCard(elevation: .low)
    }

    private func directionButton(_ title: LocalizedStringKey, active: Bool, activeBackground: Color,
                                 activeForeground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Baron.heading(11.5))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(active ? activeForeground : Baron.neutral600)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? activeBackground : Baron.inset,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recurrenceCard: some View {
        RecordToggleCard(
            title: "Repeats",
            hint: isRecurring
                ? String(localized: "Logging one occurrence offers the next.", bundle: .appPreferred, locale: .appPreferred)
                : String(localized: "A one-off. Turn this on for anything on a cycle.", bundle: .appPreferred, locale: .appPreferred),
            isOn: isRecurring,
            onToggle: { isRecurring.toggle() }
        ) {
            RecordChipPicker(options: RecurrenceInterval.allCases, selection: interval,
                             title: { $0.displayName }) { interval = $0 }
        }
    }

    private var watchCard: some View {
        RecordToggleCard(
            title: "Watch it on the timeline",
            hint: hasDueDate
                ? String(localized: "Counts toward the Timeline's net figure, and toward Overdue once the date passes.", bundle: .appPreferred, locale: .appPreferred)
                : String(localized: "Off means this is history only — it never appears on the Timeline.", bundle: .appPreferred, locale: .appPreferred),
            isOn: hasDueDate,
            onToggle: { hasDueDate.toggle() }
        ) {
            RecordField(label: "Due") {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker("", selection: dueDateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Baron.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if projectsDueDate {
                        Text("Following the series — edit to take it over.")
                            .font(Baron.body(11.5))
                            .foregroundStyle(Baron.neutral600)
                    }
                }
            }
            RecordDaySlider(label: "Appears this long before", value: $messageDaysBefore, zeroLabel: "on the day")
            RecordDaySlider(label: "Stays overdue this long after", value: $messageDaysAfter, zeroLabel: "not at all")
            notifyBlock
        }
    }

    @ViewBuilder
    private var notifyBlock: some View {
        Divider().overlay(Baron.line)
        DeviceNotificationControl(
            isOn: $deviceNotificationOn,
            scheduler: store.notificationScheduler,
            onAuthorizationGranted: { store.requestNotificationResync() }
        ) {
            RecordDaySlider(label: "Alert lead time", value: $deviceNotificationDaysBefore, zeroLabel: "same day")
            #if DEBUG
            Button("Send a test notification now") {
                let body = NotificationPlanner.transactionDueBody(kind: kind, amount: parsedAmount ?? 0,
                                                                  notes: notes, daysBefore: deviceNotificationDaysBefore)
                store.notificationScheduler?.fireDebugNotification(title: assetName, body: body,
                                                                   assetID: assetID, kind: .transaction)
            }
            .font(Baron.body(12, .medium))
            .foregroundStyle(Baron.accent800)
            #endif
        }
    }

    private var payeeCard: some View {
        RecordField(label: "Who it was with") {
            HStack(spacing: 9) {
                if payeeContactID != nil {
                    Text(payeeName.isEmpty ? String(localized: "(not found)", bundle: .appPreferred, locale: .appPreferred) : payeeName)
                        .font(Baron.body(14, .medium))
                        .foregroundStyle(payeeName.isEmpty ? Baron.neutral500 : Baron.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    smallAction("Change") { contactPickerPresented = true }
                    smallAction("Clear", tint: Baron.danger) {
                        payeeContactID = nil
                        payeeName = ""
                    }
                } else {
                    smallAction("Choose a contact…") { contactPickerPresented = true }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .baronCard(radius: Baron.Radius.field, elevation: .low)
        }
    }

    private func smallAction(_ title: LocalizedStringKey, tint: Color = Baron.accent800,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Baron.body(12, .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                    .strokeBorder(Baron.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
