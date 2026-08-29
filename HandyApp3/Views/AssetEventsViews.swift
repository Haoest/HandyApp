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
    /// row; recurring items are never collapsed. Fixed at `AppPreference.nonRecurringLimitDefault`
    /// (the Preferences screen that used to tune this was removed).
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
    /// Series source this sheet is logging a new occurrence from ("Log & Edit"), used to
    /// re-project the due date as the occurrence date changes. Nil for plain add/edit.
    let prefill: Event?
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
    /// True while the due date is still derived from the series rather than typed by the user.
    /// Set only for "Log & Edit" on a recurring source that has a due date to project from, and
    /// cleared for good the first time the user edits the field. Deliberately per-sheet-instance
    /// state, not persisted: cancelling and reopening starts the projection fresh.
    @State private var dueDateAutoManaged: Bool
    /// Same idea as `dueDateAutoManaged`, for the title. Set only for "Log & Edit" on a
    /// recurring source.
    @State private var titleAutoManaged: Bool
    /// The last value this sheet itself wrote into `title` — lets `.onChange(of: title)` tell
    /// "the projection just updated this" from "the user typed something" without a custom
    /// `Binding` (which `.limitLength`'s truncation write-back would attribute to the wrong
    /// side; see its doc comment).
    @State private var lastAutoTitle: String

    init(existing: Event? = nil, prefill: Event? = nil, prefillTitle: String? = nil, prefillDue: DueSettings? = nil,
         seriesCount: Int = 1, assetName: String, assetID: UUID, onSave: @escaping (String, Date, String, RecurrenceInterval?, DueSettings) -> Void) {
        self.existing = existing
        self.prefill = prefill
        self.seriesCount = seriesCount
        self.assetName = assetName
        self.assetID = assetID
        self.onSave = onSave
        let source = existing ?? prefill
        let initialTitle = prefillTitle ?? source?.title ?? ""
        _title = State(initialValue: initialTitle)
        _lastAutoTitle = State(initialValue: initialTitle)
        _titleAutoManaged = State(initialValue: existing == nil && prefill?.recurrence != nil)
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
        _dueDateAutoManaged = State(initialValue: existing == nil && prefill?.recurrence != nil && due.dueDate != nil)
    }

    /// Whether the due date is currently being kept in step with the occurrence date. Toggling
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

    /// Re-anchors the due date on the series whenever the occurrence date — or the interval the
    /// projection walks by — changes, until the user takes the field over.
    private func projectDueDate() {
        guard projectsDueDate, let source = prefill else { return }
        let siblings = store.assets[assetID]?.liveEvents ?? []
        guard let projected = SeriesLogic.projectedDueDate(for: source, in: siblings, occurrenceDate: date, interval: interval) else { return }
        dueDate = projected
    }

    private var projectsTitle: Bool { titleAutoManaged && isRecurring }

    /// Re-derives the title from the series' `yyyy-MM` stamping rule (`suggestedDuplicateTitle`
    /// → `SeriesLogic.duplicateTitle`) whenever the occurrence date changes, until the user
    /// takes the field over. Writes `lastAutoTitle` before `title` so the resulting
    /// `.onChange(of: title)` sees its own write and leaves the flag alone.
    private func projectTitle() {
        guard projectsTitle, let source = prefill else { return }
        let projected = TextLimits.clamp(store.suggestedDuplicateTitle(forEventID: source.id, onAssetID: assetID, at: date), to: TextLimits.eventTitle)
        lastAutoTitle = projected
        title = projected
    }

    var body: some View {
        RecordSheetScaffold(
            title: existing == nil ? "New event" : "Edit event",
            saveLabel: "Save",
            canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty,
            onSave: save
        ) {
            RecordField(label: "What happened") {
                TextField("Oil change, inspection, repair…", text: $title)
                    .limitLength(TextLimits.eventTitle, text: $title)
                    .recordInput()
            }
            RecordDateField(label: "Date", date: $date)
            recurrenceCard
            watchCard
            RecordField(label: "Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
                    .lineLimit(3...)
                    .limitLength(TextLimits.eventNotes, text: $notes)
                    .recordInput()
            }
            if seriesCount > 1 {
                Text("This series has ^[\(seriesCount) event](inflect: true).")
                    .font(Baron.body(12.5))
                    .foregroundStyle(Baron.neutral600)
            }
        }
        .onChange(of: date) { _, _ in
            projectDueDate()
            projectTitle()
        }
        .onChange(of: interval) { _, _ in projectDueDate() }
        .onChange(of: title) { _, newValue in
            guard titleAutoManaged, newValue != lastAutoTitle else { return }
            titleAutoManaged = false
        }
    }

    private func save() {
        let due = DueSettings(dueDate: hasDueDate ? dueDate : nil, messageDaysBefore: messageDaysBefore,
                              messageDaysAfter: messageDaysAfter, deviceNotificationOn: deviceNotificationOn,
                              deviceNotificationDaysBefore: deviceNotificationDaysBefore)
        onSave(title.trimmingCharacters(in: .whitespaces), date, notes.trimmingCharacters(in: .whitespaces),
               isRecurring ? interval : nil, due)
    }

    private var recurrenceCard: some View {
        RecordToggleCard(
            title: "Repeats",
            hint: isRecurring
                ? String(localized: "Logging one occurrence offers the next.")
                : String(localized: "A one-off. Turn this on for anything on a cycle."),
            isOn: isRecurring,
            onToggle: { isRecurring.toggle() }
        ) {
            RecordChipPicker(options: RecurrenceInterval.allCases, selection: interval,
                             title: { $0.rawValue }) { interval = $0 }
        }
    }

    private var watchCard: some View {
        RecordToggleCard(
            title: "Watch it on the timeline",
            hint: hasDueDate
                ? String(localized: "Shows up under Coming up, and counts toward Overdue once the date passes.")
                : String(localized: "Off means this is history only — it never appears on the Timeline."),
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
        Button { deviceNotificationOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell")
                    .font(.system(size: 14))
                    .foregroundStyle(deviceNotificationOn ? Baron.accent800 : Baron.neutral600)
                    .frame(width: 32, height: 32)
                    .background(deviceNotificationOn ? Baron.accent100 : Baron.inset,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Notify me on this device")
                    .font(Baron.body(14, .medium))
                    .foregroundStyle(Baron.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ToggleTrack(isOn: deviceNotificationOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if deviceNotificationOn {
            RecordDaySlider(label: "Alert lead time", value: $deviceNotificationDaysBefore, zeroLabel: "same day")
            #if DEBUG
            Button("Send a test notification now") {
                let body = NotificationPlanner.eventDueBody(title: title, notes: notes, daysBefore: deviceNotificationDaysBefore)
                store.notificationScheduler?.fireDebugNotification(title: assetName, body: body, assetID: assetID, kind: .event)
            }
            .font(Baron.body(12, .medium))
            .foregroundStyle(Baron.accent800)
            #endif
        }
    }
}
