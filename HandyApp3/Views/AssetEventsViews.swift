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
    /// Called when a creation action is blocked by the free-tier event limit.
    /// The paywall itself is presented by the owner (see AssetDetailView's
    /// note on why sheets can't live at the section/row level).
    let onLimitReached: () -> Void

    /// Non-recurring items shown inline before collapsing behind the "Show All"
    /// row; recurring items are never collapsed. User-tunable in Preferences.
    @AppStorage(AppPreference.eventLimitKey)
    private var nonRecurringLimit = AppPreference.nonRecurringLimitDefault

    private var sorted: [Event] { asset.events.recurringFirstDateDescending() }

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
        Section("Events") {
            if asset.events.isEmpty {
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
        }
    }
}

struct EventListView: View {
    let asset: Asset
    @Binding var sheetMode: EventSheetMode?
    let onLimitReached: () -> Void

    private var sorted: [Event] { asset.events.recurringFirstDateDescending() }

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
                        try? store.addEvent(title: event.title, date: Date(), notes: event.notes, toAssetID: asset.id)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    if store.hasEventCapacity(for: asset) {
                        sheetMode = .duplicate(event)
                    } else {
                        onLimitReached()
                    }
                } label: {
                    Label("Duplicate…", systemImage: "square.and.pencil")
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
    let existing: Event?
    let onSave: (String, Date, String, RecurrenceInterval?) -> Void

    @State private var title: String
    @State private var date: Date
    @State private var notes: String
    @State private var isRecurring: Bool
    @State private var interval: RecurrenceInterval

    init(existing: Event? = nil, prefill: Event? = nil, onSave: @escaping (String, Date, String, RecurrenceInterval?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        let source = existing ?? prefill
        _title = State(initialValue: source?.title ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _notes = State(initialValue: source?.notes ?? "")
        // Recurrence intentionally doesn't carry over from a duplicate prefill —
        // a copy starts non-recurring so duplication can't silently double reminders.
        _isRecurring = State(initialValue: existing?.recurrence != nil)
        _interval = State(initialValue: existing?.recurrence ?? .monthly)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Event title", text: $title)
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
            }
            .navigationTitle(existing == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title.trimmingCharacters(in: .whitespaces), date, notes.trimmingCharacters(in: .whitespaces), isRecurring ? interval : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
