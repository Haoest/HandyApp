import SwiftUI

/// Cross-asset view of recent and recurring events/transactions — see `LedgerDigest` for the
/// selection/grouping/sort rules. Sheets are owned here, not by the row/header (same reason as
/// `AssetDetailContent`'s add/edit sheets: a section-level sheet gets torn down when that
/// section's body re-evaluates during the first present).
struct EventsTransactionsTab: View {
    @Environment(AssetStore.self) private var store

    @AppStorage(AppPreference.ledgerFilterModeKey)
    private var filterModeRaw: String = LedgerFilterMode.all.rawValue
    @AppStorage(AppPreference.ledgerWindowMonthsKey)
    private var windowMonths: Int = LedgerDigest.defaultWindowMonths

    @State private var addEventTarget: AddTarget?
    @State private var addTransactionTarget: AddTarget?
    @State private var eventToLogEdit: ResolvedEvent?
    @State private var transactionToLogEdit: ResolvedTransaction?
    @State private var paywallPresented = false
    @State private var paywallReason: PaywallReason = .events

    private var filterMode: LedgerFilterMode { LedgerFilterMode(rawValue: filterModeRaw) ?? .all }

    private var groups: [LedgerAssetGroup] {
        let sources = store.allAssets.map { asset in
            LedgerSource(assetID: asset.id, assetName: asset.name, events: asset.liveEvents, transactions: asset.liveTransactions)
        }
        return LedgerDigest.build(sources: sources, mode: filterMode, windowMonths: windowMonths)
    }

    private var isFilterActive: Bool { filterMode != .all || windowMonths != LedgerDigest.defaultWindowMonths }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                content
                    .scrollContentBackground(.hidden)
                    // Background is always a light gradient — pin the scheme light so
                    // labels stay dark for contrast even in system dark mode.
                    .environment(\.colorScheme, .light)
            }
            .navigationTitle("Logs")
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .sheet(item: $addEventTarget) { target in
                EventEditView(assetName: target.assetName, assetID: target.assetID) { title, date, notes, recurrence, due in
                    try? store.addEvent(title: title, date: date, notes: notes, recurrence: recurrence, due: due, toAssetID: target.assetID)
                }
            }
            .sheet(item: $addTransactionTarget) { target in
                TransactionEditView(assetName: target.assetName, assetID: target.assetID) { details, amount, date, kind, payeeID, notes, recurrence, due in
                    try? store.addTransaction(details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due, toAssetID: target.assetID)
                }
            }
            .sheet(item: $eventToLogEdit) { resolved in
                let source = resolved.event
                EventEditView(
                    prefill: source,
                    prefillTitle: store.suggestedDuplicateTitle(forEventID: source.id, onAssetID: resolved.assetID),
                    prefillDue: DueSettings(dueDate: SeriesLogic.advancedDueDate(for: source), messageDaysBefore: source.messageDaysBefore, messageDaysAfter: source.messageDaysAfter, deviceNotificationOn: source.deviceNotificationOn, deviceNotificationDaysBefore: source.deviceNotificationDaysBefore),
                    assetName: liveAsset(resolved.assetID)?.name ?? "",
                    assetID: resolved.assetID
                ) { title, date, notes, recurrence, due in
                    try? store.duplicateEvent(id: source.id, onAssetID: resolved.assetID, title: title, date: date, notes: notes, recurrence: recurrence, due: due)
                }
            }
            .sheet(item: $transactionToLogEdit) { resolved in
                let source = resolved.transaction
                TransactionEditView(
                    prefill: source,
                    prefillDetails: store.suggestedDuplicateTitle(forTransactionID: source.id, onAssetID: resolved.assetID),
                    prefillDue: DueSettings(dueDate: SeriesLogic.advancedDueDate(for: source), messageDaysBefore: source.messageDaysBefore, messageDaysAfter: source.messageDaysAfter, deviceNotificationOn: source.deviceNotificationOn, deviceNotificationDaysBefore: source.deviceNotificationDaysBefore),
                    assetName: liveAsset(resolved.assetID)?.name ?? "",
                    assetID: resolved.assetID
                ) { details, amount, date, kind, payeeID, notes, recurrence, due in
                    try? store.duplicateTransaction(id: source.id, onAssetID: resolved.assetID, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due)
                }
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallView(reason: paywallReason)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "No Events or Transactions",
                systemImage: "list.bullet.clipboard",
                description: Text("Events and transactions logged on your assets will show up here.")
            )
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            LedgerEntryRow(
                                entry: entry,
                                onLogNow: { logNow(entry, assetID: group.assetID) },
                                onLogEdit: { logEdit(entry, assetID: group.assetID) }
                            )
                            .listRowBackground(Color.white.opacity(0.5))
                        }
                    } header: {
                        GroupHeader(
                            assetName: group.assetName,
                            onAddEvent: { requestAddEvent(for: group) },
                            onAddTransaction: { requestAddTransaction(for: group) }
                        )
                    }
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $filterModeRaw) {
                Text("All").tag(LedgerFilterMode.all.rawValue)
                Text("Events Only").tag(LedgerFilterMode.eventsOnly.rawValue)
                Text("Transactions Only").tag(LedgerFilterMode.transactionsOnly.rawValue)
                Text("Late Only").tag(LedgerFilterMode.lateOnly.rawValue)
            }
            Picker("History", selection: $windowMonths) {
                ForEach(AppPreference.ledgerWindowMonthsOptions, id: \.self) { months in
                    Text("^[\(months) month](inflect: true)").tag(months)
                }
            }
        } label: {
            Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Actions

    private func liveAsset(_ id: UUID) -> Asset? {
        guard let asset = store.assets[id], !asset.isDeleted, !asset.isPurged else { return nil }
        return asset
    }

    private func requestAddEvent(for group: LedgerAssetGroup) {
        guard let asset = liveAsset(group.assetID) else { return }
        if store.hasEventCapacity(for: asset) {
            addEventTarget = AddTarget(assetID: asset.id, assetName: asset.name)
        } else {
            paywallReason = .events
            paywallPresented = true
        }
    }

    private func requestAddTransaction(for group: LedgerAssetGroup) {
        guard let asset = liveAsset(group.assetID) else { return }
        if store.hasTransactionCapacity(for: asset) {
            addTransactionTarget = AddTarget(assetID: asset.id, assetName: asset.name)
        } else {
            paywallReason = .transactions
            paywallPresented = true
        }
    }

    private func logNow(_ entry: LedgerEntry, assetID: UUID) {
        guard let asset = liveAsset(assetID) else { return }
        switch entry {
        case .event(let event, _):
            if store.hasEventCapacity(for: asset) {
                try? store.duplicateEvent(id: event.id, onAssetID: assetID)
            } else {
                paywallReason = .events
                paywallPresented = true
            }
        case .transaction(let transaction, _):
            if store.hasTransactionCapacity(for: asset) {
                try? store.duplicateTransaction(id: transaction.id, onAssetID: assetID)
            } else {
                paywallReason = .transactions
                paywallPresented = true
            }
        }
    }

    private func logEdit(_ entry: LedgerEntry, assetID: UUID) {
        guard let asset = liveAsset(assetID) else { return }
        switch entry {
        case .event(let event, _):
            if store.hasEventCapacity(for: asset) {
                eventToLogEdit = ResolvedEvent(event: event, assetID: assetID)
            } else {
                paywallReason = .events
                paywallPresented = true
            }
        case .transaction(let transaction, _):
            if store.hasTransactionCapacity(for: asset) {
                transactionToLogEdit = ResolvedTransaction(transaction: transaction, assetID: assetID)
            } else {
                paywallReason = .transactions
                paywallPresented = true
            }
        }
    }
}

// MARK: - Group header

private struct GroupHeader: View {
    let assetName: String
    let onAddEvent: () -> Void
    let onAddTransaction: () -> Void

    var body: some View {
        HStack {
            Text(assetName)
            Spacer()
            Button(action: onAddEvent) {
                Image(systemName: "calendar.badge.plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add Event")
            Button(action: onAddTransaction) {
                Image(systemName: "dollarsign.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add Transaction")
        }
    }
}

// MARK: - Entry row

private struct LedgerEntryRow: View {
    let entry: LedgerEntry
    let onLogNow: () -> Void
    let onLogEdit: () -> Void

    private var isRecurring: Bool { entry.facts != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if isRecurring {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                sentenceText
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isRecurring {
                HStack(spacing: 20) {
                    Button(action: onLogNow) {
                        Label("Log Now", systemImage: "plus.square.on.square")
                    }
                    Button(action: onLogEdit) {
                        Label("Log & Edit", systemImage: "square.and.pencil")
                    }
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var lateSuffix: Text {
        Text(verbatim: " ") + Text("(Late)").foregroundColor(.red)
    }

    private var sentenceText: Text {
        switch entry {
        case .event(let event, let facts):
            let dateText = event.date.formatted(date: .abbreviated, time: .omitted)
            let title = event.title
            guard let facts else {
                return Text("\(title): event happened on \(dateText)")
            }
            let nextText = facts.nextExpected.formatted(date: .abbreviated, time: .omitted)
            let base = Text("\(title): event happened on \(dateText), next expected event on \(nextText).")
            return facts.isLate ? base + lateSuffix : base

        case .transaction(let transaction, let facts):
            let amountText = transaction.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
            let dateText = transaction.date.formatted(date: .abbreviated, time: .omitted)
            let details = transaction.details
            guard let facts else {
                let base = transaction.kind == .income
                    ? Text("\(details): payment \(amountText) received on \(dateText)")
                    : Text("\(details): payment \(amountText) paid out on \(dateText)")
                return base
            }
            let nextText = facts.nextExpected.formatted(date: .abbreviated, time: .omitted)
            let base = transaction.kind == .income
                ? Text("\(details): \(amountText) received on \(dateText). Next expected payment on \(nextText).")
                : Text("\(details): \(amountText) paid out on \(dateText). Next expected payment on \(nextText).")
            return facts.isLate ? base + lateSuffix : base
        }
    }
}

// MARK: - Sheet targets

/// Asset name + id, used to open an add-event/add-transaction sheet for a group's asset.
private struct AddTarget: Identifiable {
    let assetID: UUID
    let assetName: String
    var id: UUID { assetID }
}

/// Sheet items pairing a record with its owning asset id, needed by the store's
/// duplicate methods when saving from the Log & Edit sheets.
private struct ResolvedEvent: Identifiable {
    let event: Event
    let assetID: UUID
    var id: UUID { event.id }
}

private struct ResolvedTransaction: Identifiable {
    let transaction: Transaction
    let assetID: UUID
    var id: UUID { transaction.id }
}
