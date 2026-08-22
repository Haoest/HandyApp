import SwiftUI

// MARK: - Recurring-first ordering

private extension Array where Element == Event {
    func recurringFirstDateDescending() -> [Event] {
        sorted {
            if ($0.recurrence != nil) != ($1.recurrence != nil) { return $0.recurrence != nil }
            return $0.date > $1.date
        }
    }
}

// MARK: - Events section

enum EventSheetMode: Identifiable {
    case edit(Event)
    case duplicate(Event)

    var id: UUID {
        switch self {
        case .edit(let event), .duplicate(let event): event.id
        }
    }
}

struct EventsSection: View {
    let asset: Asset
    @Binding var sheetMode: EventSheetMode?
    let onAdd: () -> Void
    /// Called when a creation action is blocked by the free-tier event limit.
    /// The paywall itself is presented by the owner (see AssetDetailView's
    /// note on why sheets can't live at the section/row level).
    let onLimitReached: () -> Void

    /// Non-recurring items shown inline before collapsing behind the "Show All"
    /// row; recurring items are never collapsed. User-tunable in Preferences.
    @AppStorage(AppPreference.eventLimitKey)
    private var nonRecurringLimit = AppPreference.nonRecurringLimitDefault

    private var sorted: [Event] { asset.liveEvents.recurringFirstDateDescending() }

    private var displayed: [Event] {
        var remaining = nonRecurringLimit
        return sorted.filter { event in
            guard event.recurrence == nil else { return true }
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
                ForEach(displayed) { event in
                    EventItemRow(asset: asset, event: event, sheetMode: $sheetMode, onLimitReached: onLimitReached)
                        .pagingExcludedRow(id: event.id.uuidString)
                }
                if hasMore {
                    NavigationLink {
                        EventListView(asset: asset, sheetMode: $sheetMode, onLimitReached: onLimitReached)
                    } label: {
                        Text("Show All").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            AddSectionHeader(title: "Events", action: onAdd)
        }
    }
}

struct EventListView: View {
    let asset: Asset
    @Binding var sheetMode: EventSheetMode?
    let onLimitReached: () -> Void

    private var sorted: [Event] { asset.liveEvents.recurringFirstDateDescending() }

    var body: some View {
        List {
            ForEach(sorted) { event in
                EventItemRow(asset: asset, event: event, sheetMode: $sheetMode, onLimitReached: onLimitReached)
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EventItemRow: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    let event: Event
    @Binding var sheetMode: EventSheetMode?
    let onLimitReached: () -> Void

    /// Recurring events join (or start) a series when duplicated — "Log" wording signals
    /// that, versus a plain "Duplicate" for a one-off copy.
    private var quickActionTitle: LocalizedStringKey { event.recurrence != nil ? "Log Now" : "Duplicate" }
    private var reviewActionTitle: LocalizedStringKey { event.recurrence != nil ? "Log & Edit" : "Duplicate & Edit" }

    var body: some View {
        EventRow(event: event)
            .contentShape(Rectangle())
            .onTapGesture { sheetMode = .edit(event) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    try? store.removeEvent(id: event.id, fromAssetID: asset.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    if store.hasEventCapacity(for: asset) {
                        try? store.duplicateEvent(id: event.id, onAssetID: asset.id)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label(quickActionTitle, systemImage: "plus.square.on.square")
                }
                Button {
                    if store.hasEventCapacity(for: asset) {
                        sheetMode = .duplicate(event)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label(reviewActionTitle, systemImage: "square.and.pencil")
                }
            }
    }
}

private struct EventRow: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .fontWeight(.medium)
            HStack(spacing: 6) {
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                if let recurrence = event.recurrence {
                    Label(recurrence.rawValue, systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !event.notes.isEmpty {
                Text(event.notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Event edit sheet

struct EventEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AssetStore.self) private var store
    let existing: Event?
    let seriesCount: Int
    /// Asset name and ID, used only by the debug "send test notification" button to
    /// mirror the real notification's title and tap-routing target.
    let assetName: String
    let assetID: UUID
    let onSave: (String, Date, String, RecurrenceInterval?, DueSettings) -> Void

    @State private var title: String
    @State private var date: Date
    @State private var notes: String
    @State private var isRecurring: Bool
    @State private var interval: RecurrenceInterval
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var messageDaysBefore: Int
    @State private var messageDaysAfter: Int
    @State private var deviceNotificationOn: Bool
    @State private var deviceNotificationDaysBefore: Int

    init(existing: Event? = nil, prefill: Event? = nil, prefillTitle: String? = nil, prefillDue: DueSettings? = nil,
         seriesCount: Int = 1, assetName: String, assetID: UUID, onSave: @escaping (String, Date, String, RecurrenceInterval?, DueSettings) -> Void) {
        self.existing = existing
        self.seriesCount = seriesCount
        self.assetName = assetName
        self.assetID = assetID
        self.onSave = onSave
        let source = existing ?? prefill
        _title = State(initialValue: prefillTitle ?? source?.title ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _notes = State(initialValue: source?.notes ?? "")
        // A series duplicate inherits recurrence from its source so the chain of occurrences
        // keeps repeating; NotificationPlanner schedules reminders from only the newest
        // occurrence of a series so this can't double them up.
        _isRecurring = State(initialValue: source?.recurrence != nil)
        _interval = State(initialValue: source?.recurrence ?? .monthly)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Event title", text: $title)
                    if seriesCount > 1 {
                        Text("This series has ^[\(seriesCount) event](inflect: true)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Date of Event") {
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
                                store.notificationScheduler?.fireDebugNotification(title: assetName, body: title, assetID: assetID, kind: .event)
                            }
                            #endif
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle(existing == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let due = DueSettings(dueDate: hasDueDate ? dueDate : nil, messageDaysBefore: messageDaysBefore,
                                              messageDaysAfter: messageDaysAfter, deviceNotificationOn: deviceNotificationOn,
                                              deviceNotificationDaysBefore: deviceNotificationDaysBefore)
                        onSave(title.trimmingCharacters(in: .whitespaces), date, notes.trimmingCharacters(in: .whitespaces), isRecurring ? interval : nil, due)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
