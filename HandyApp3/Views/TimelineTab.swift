import SwiftUI

/// The Timeline tab — the Baron Book redesign's merge of the old Home digest and the Logs
/// worklist into one screen: relative due windows ("Coming up") over a structured activity
/// feed ("History"), plus the global quick-log flow.
///
/// Coming-up rows come from `TimelineDigest` (one row per series, bucketed by days-until-due);
/// history rows reuse `HomeActivityDigest`'s day grouping, rendered as tappable rows rather
/// than the old sentence prose.
struct TimelineTab: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var visibleDayCount = HomeActivityDigest.pageSize
    @State private var pushedAsset: PushedAsset?

    // Quick-log flow
    @State private var quickLogStep: QuickLogStep?
    @State private var addEventTarget: AddTarget?
    @State private var addTransactionTarget: AddTarget?

    // Record sheets
    @State private var eventToEdit: ResolvedEvent?
    @State private var transactionToEdit: ResolvedTransaction?
    @State private var eventToLogEdit: ResolvedEvent?
    @State private var transactionToLogEdit: ResolvedTransaction?

    @State private var paywallReason: PaywallReason = .events
    @State private var paywallPresented = false

    // MARK: - Derived state

    private var sources: [TimelineSource] {
        store.allAssets.map {
            TimelineSource(assetID: $0.id, assetName: $0.name, events: $0.liveEvents, transactions: $0.liveTransactions)
        }
    }

    private var items: [TimelineItem] { TimelineDigest.items(sources: sources) }
    private var groups: [TimelineWindowGroup] { TimelineDigest.groups(from: items) }
    private var summary: TimelineSummary { TimelineDigest.summary(from: items) }

    private var days: [HomeDay] {
        HomeActivityDigest.build(from: store.activityLog, dayLimit: visibleDayCount)
    }

    private var hasMoreDays: Bool {
        HomeActivityDigest.activeDayCount(in: store.activityLog) > visibleDayCount
    }

    private var isEmpty: Bool { items.isEmpty && store.activityLog.isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Baron.background.ignoresSafeArea()
                if isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            statCards.padding(.top, 16)
                            if !groups.isEmpty { comingUp.padding(.top, 24) }
                            history.padding(.top, 28)
                        }
                        .padding(.horizontal, Baron.pageInset)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $pushedAsset) { pushed in
                if let asset = store.assets[pushed.id], !asset.isDeleted, !asset.isPurged {
                    ThingDetailView(asset: asset, initialAnchor: pushed.section)
                } else {
                    ContentUnavailableView("Asset Not Found", systemImage: "shippingbox",
                                           description: Text("This asset no longer exists."))
                }
            }
            .sheet(item: $quickLogStep) { step in
                QuickLogSheet(step: step, assets: store.allAssets) { assetID, isEvent in
                    quickLogStep = nil
                    startRecord(assetID: assetID, isEvent: isEvent)
                } onPickThing: { assetID in
                    quickLogStep = .pickKind(assetID: assetID)
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
            .sheet(item: $eventToEdit) { resolved in
                let seriesCount = liveAsset(resolved.assetID).map { SeriesLogic.members(of: resolved.event, in: $0.liveEvents).count } ?? 1
                EventEditView(existing: resolved.event, seriesCount: seriesCount, assetName: liveAsset(resolved.assetID)?.name ?? "", assetID: resolved.assetID) { title, date, notes, recurrence, due in
                    try? store.updateEvent(id: resolved.event.id, onAssetID: resolved.assetID, title: title, date: date, notes: notes, recurrence: recurrence, due: due)
                }
            }
            .sheet(item: $transactionToEdit) { resolved in
                let seriesCount = liveAsset(resolved.assetID).map { SeriesLogic.members(of: resolved.transaction, in: $0.liveTransactions).count } ?? 1
                TransactionEditView(existing: resolved.transaction, seriesCount: seriesCount, assetName: liveAsset(resolved.assetID)?.name ?? "", assetID: resolved.assetID) { details, amount, date, kind, payeeID, notes, recurrence, due in
                    try? store.updateTransaction(id: resolved.transaction.id, onAssetID: resolved.assetID, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due)
                }
            }
            .sheet(item: $eventToLogEdit) { resolved in
                let source = resolved.event
                EventEditView(
                    prefill: source,
                    prefillTitle: store.suggestedDuplicateTitle(forEventID: source.id, onAssetID: resolved.assetID),
                    prefillDue: store.suggestedDuplicateDue(forEventID: source.id, onAssetID: resolved.assetID),
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
                    prefillDue: store.suggestedDuplicateDue(forTransactionID: source.id, onAssetID: resolved.assetID),
                    assetName: liveAsset(resolved.assetID)?.name ?? "",
                    assetID: resolved.assetID
                ) { details, amount, date, kind, payeeID, notes, recurrence, due in
                    try? store.duplicateTransaction(id: source.id, onAssetID: resolved.assetID, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due)
                }
            }
            .sheet(isPresented: $paywallPresented) { PaywallView(reason: paywallReason) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.datelineFormatter.string(from: Date()))
                    .font(Baron.body(12, .medium))
                    .tracking(0.5)
                    .foregroundStyle(Baron.neutral600)
                Text("Timeline")
                    .font(Baron.heading(32))
                    .foregroundStyle(Baron.text)
            }
            Spacer(minLength: 0)
            Button { quickLogStep = .pickThing } label: {
                Text("+ Log")
                    .font(Baron.heading(12.5))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(Baron.fill, in: RoundedRectangle(cornerRadius: Baron.Radius.field, style: .continuous))
            }
            .baronShadow(.high)
            .padding(.top, 12)
        }
        .padding(.top, 12)
    }

    private var statCards: some View {
        HStack(spacing: 9) {
            statCard("Overdue", value: "\(summary.overdueCount)",
                     color: summary.overdueCount > 0 ? Baron.danger : Baron.text)
            statCard("Due soon", value: "\(summary.upcomingCount)", color: Baron.text)
            statCard("Net 30 days", value: Self.money(summary.netAmount),
                     color: summary.netAmount < 0 ? Baron.danger : Baron.good)
        }
    }

    private func statCard(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(Baron.body(10, .medium))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(Baron.heading(17))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .baronCard(radius: 16, elevation: .low)
    }

    // MARK: - Coming up

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Coming up")
                    .font(Baron.heading(19))
                    .foregroundStyle(Baron.text)
                Spacer(minLength: 0)
                Text("\(items.count) watched")
                    .font(Baron.body(12, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 11) {
                    windowHeader(group)
                    ForEach(group.items) { item in
                        ComingUpRow(
                            item: item,
                            onLogNow: { logNow(item) },
                            onLogEdit: { logEdit(item) },
                            onOpenThing: { pushedAsset = PushedAsset(id: item.assetID, section: item.isEvent ? .events : .transactions) }
                        )
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    private func windowHeader(_ group: TimelineWindowGroup) -> some View {
        HStack(spacing: 8) {
            Text(Self.windowLabel(group.window))
                .font(Baron.heading(11))
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(group.window == .overdue ? Baron.danger : Baron.neutral700)
            Rectangle()
                .fill(Baron.neutral300)
                .frame(height: 1)
            Text(group.hasMoney
                 ? Self.money(group.netAmount)
                 : "\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
                .font(Baron.body(11, .medium))
                .foregroundStyle(Baron.neutral600)
        }
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("History")
                    .font(Baron.heading(19))
                    .foregroundStyle(Baron.text)
                Spacer(minLength: 0)
                Text("newest first")
                    .font(Baron.body(12, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.dayFormatter.string(from: group.day))
                        .font(Baron.heading(11))
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Baron.neutral600)
                    VStack(spacing: 7) {
                        ForEach(group.rows) { row in
                            if let display = historyRow(for: row) {
                                HistoryRowView(display: display) { open(display.target) }
                            }
                        }
                    }
                }
                .padding(.top, 14)
            }
            Button {
                visibleDayCount += HomeActivityDigest.pageSize
            } label: {
                Text(hasMoreDays ? "Show earlier" : "End of history")
                    .font(Baron.heading(11.5))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(hasMoreDays ? Baron.accent800 : Baron.neutral500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: Baron.Radius.field, style: .continuous)
                            .strokeBorder(Baron.neutral300, lineWidth: 1)
                    )
            }
            .disabled(!hasMoreDays)
            .padding(.top, 14)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing yet",
            systemImage: "waveform",
            description: Text("Things you add, and the records you log against them, show up here.")
        )
    }

    // MARK: - History row construction

    private func historyRow(for row: HomeRow) -> HistoryDisplay? {
        switch row {
        case .summary(let kind, let assetID, let count, _):
            guard let asset = liveAsset(assetID) else { return nil }
            return HistoryDisplay(
                id: "summary-\(kind.rawValue)-\(assetID.uuidString)",
                title: "\(count) \(Self.noun(kind, count: count)) added",
                subtitle: asset.name,
                amount: nil,
                isMoney: kind == .transaction,
                target: .asset(assetID, Self.anchor(for: kind))
            )

        case .single(let entry):
            let time = entry.timestamp.formatted(date: .omitted, time: .shortened)
            switch entry.kind {
            case .asset:
                guard let asset = liveAsset(entry.recordID) else { return nil }
                return HistoryDisplay(id: entry.id.uuidString, title: "\(asset.name) added",
                                      subtitle: "New thing · \(time)", amount: nil, isMoney: false,
                                      target: .asset(asset.id, nil))

            case .event:
                guard let asset = entry.owningAssetID.flatMap(liveAsset),
                      let event = asset.liveEvents.first(where: { $0.id == entry.recordID }) else { return nil }
                return HistoryDisplay(id: entry.id.uuidString, title: "\(event.title) logged",
                                      subtitle: "\(asset.name) · \(time)", amount: nil, isMoney: false,
                                      target: .event(asset.id, event.id))

            case .transaction:
                guard let asset = entry.owningAssetID.flatMap(liveAsset),
                      let txn = asset.liveTransactions.first(where: { $0.id == entry.recordID }) else { return nil }
                let signed = txn.kind == .expense ? -txn.amount : txn.amount
                return HistoryDisplay(id: entry.id.uuidString, title: "\(txn.details) — \(asset.name)",
                                      subtitle: "\(txn.kind == .expense ? "Money out" : "Money in") · \(time)",
                                      amount: signed, isMoney: true,
                                      target: .transaction(asset.id, txn.id))

            case .photo:
                guard let asset = entry.owningAssetID.flatMap(liveAsset) else { return nil }
                let caption = asset.livePhotos.first { $0.id == entry.recordID }?.caption
                    .trimmingCharacters(in: .whitespaces) ?? ""
                return HistoryDisplay(id: entry.id.uuidString,
                                      title: caption.isEmpty ? "Photo added" : "Photo “\(caption)” added",
                                      subtitle: "\(asset.name) · \(time)", amount: nil, isMoney: false,
                                      target: .asset(asset.id, .photos))
            }
        }
    }

    private func open(_ target: HistoryTarget) {
        switch target {
        case .asset(let id, let anchor):
            pushedAsset = PushedAsset(id: id, section: anchor)
        case .event(let assetID, let eventID):
            guard let asset = liveAsset(assetID), let event = asset.liveEvents.first(where: { $0.id == eventID }) else { return }
            eventToEdit = ResolvedEvent(event: event, assetID: assetID)
        case .transaction(let assetID, let txnID):
            guard let asset = liveAsset(assetID), let txn = asset.liveTransactions.first(where: { $0.id == txnID }) else { return }
            transactionToEdit = ResolvedTransaction(transaction: txn, assetID: assetID)
        }
    }

    // MARK: - Actions

    private func liveAsset(_ id: UUID) -> Asset? {
        guard let asset = store.assets[id], !asset.isDeleted, !asset.isPurged else { return nil }
        return asset
    }

    private func startRecord(assetID: UUID, isEvent: Bool) {
        guard let asset = liveAsset(assetID) else { return }
        if isEvent {
            guard store.hasEventCapacity(for: asset) else { return present(.events) }
            addEventTarget = AddTarget(assetID: asset.id, assetName: asset.name)
        } else {
            guard store.hasTransactionCapacity(for: asset) else { return present(.transactions) }
            addTransactionTarget = AddTarget(assetID: asset.id, assetName: asset.name)
        }
    }

    private func logNow(_ item: TimelineItem) {
        guard let asset = liveAsset(item.assetID) else { return }
        if item.isEvent {
            guard store.hasEventCapacity(for: asset) else { return present(.events) }
            try? store.duplicateEvent(id: item.openRecordID, onAssetID: item.assetID)
        } else {
            guard store.hasTransactionCapacity(for: asset) else { return present(.transactions) }
            try? store.duplicateTransaction(id: item.openRecordID, onAssetID: item.assetID)
        }
    }

    private func logEdit(_ item: TimelineItem) {
        guard let asset = liveAsset(item.assetID) else { return }
        if item.isEvent {
            guard store.hasEventCapacity(for: asset) else { return present(.events) }
            guard let event = asset.liveEvents.first(where: { $0.id == item.openRecordID }) else { return }
            eventToLogEdit = ResolvedEvent(event: event, assetID: item.assetID)
        } else {
            guard store.hasTransactionCapacity(for: asset) else { return present(.transactions) }
            guard let txn = asset.liveTransactions.first(where: { $0.id == item.openRecordID }) else { return }
            transactionToLogEdit = ResolvedTransaction(transaction: txn, assetID: item.assetID)
        }
    }

    private func present(_ reason: PaywallReason) {
        paywallReason = reason
        paywallPresented = true
    }

    // MARK: - Formatting

    static func money(_ amount: Decimal) -> String {
        let code = Locale.current.currency?.identifier ?? "USD"
        let magnitude = abs(amount).formatted(.currency(code: code).precision(.fractionLength(0...2)))
        return (amount < 0 ? "−" : "+") + magnitude
    }

    static func windowLabel(_ window: TimelineWindow) -> String {
        switch window {
        case .overdue: return String(localized: "Overdue")
        case .thisWeek: return String(localized: "This week")
        case .nextTwoWeeks: return String(localized: "Next two weeks")
        case .laterThisMonth: return String(localized: "Later this month")
        }
    }

    private static func noun(_ kind: LoggedRecordKind, count: Int) -> String {
        switch kind {
        case .photo: return count == 1 ? "photo" : "photos"
        case .event: return count == 1 ? "event" : "events"
        case .transaction: return count == 1 ? "transaction" : "transactions"
        case .asset: return count == 1 ? "thing" : "things"
        }
    }

    private static func anchor(for kind: LoggedRecordKind) -> DetailAnchor? {
        switch kind {
        case .photo: return .photos
        case .event: return .events
        case .transaction: return .transactions
        case .asset: return nil
        }
    }

    private static let datelineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

// MARK: - Coming-up row

private struct ComingUpRow: View {
    let item: TimelineItem
    let onLogNow: () -> Void
    let onLogEdit: () -> Void
    let onOpenThing: () -> Void

    private var edgeColor: Color {
        if item.isOverdue { return Baron.danger }
        if let amount = item.signedAmount, amount > 0 { return Baron.good }
        return Baron.accent500
    }

    private var whenText: String {
        switch item.daysUntilDue {
        case ..<0: return "\(abs(item.daysUntilDue))d late"
        case 0: return String(localized: "today")
        default: return "in \(item.daysUntilDue)d"
        }
    }

    private var meta: String {
        var parts = [item.assetName]
        if let interval = item.interval { parts.append(interval.rawValue) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Text(item.isEvent ? "◷" : "$")
                    .font(Baron.heading(13))
                    .foregroundStyle(item.isOverdue ? Baron.danger : Baron.accent800)
                    .frame(width: 36, height: 36)
                    .background(item.isOverdue ? Baron.dangerBackground : Baron.accent100,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(Baron.heading(16))
                        .foregroundStyle(Baron.text)
                        .lineLimit(2)
                    Text(meta)
                        .font(Baron.body(12.5))
                        .foregroundStyle(Baron.neutral600)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    if let amount = item.signedAmount {
                        Text(TimelineTab.money(amount))
                            .font(Baron.body(14.5, .semibold))
                            .foregroundStyle(amount < 0 ? Baron.danger : Baron.good)
                    }
                    Text(whenText)
                        .font(Baron.body(11, .medium))
                        .foregroundStyle(item.isOverdue ? Baron.danger : Baron.neutral600)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 8) {
                Button(action: onLogNow) {
                    Text(item.isSeriesEligible ? "Log it" : "Duplicate")
                        .font(Baron.heading(11.5))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Baron.accent800)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Baron.accent100, in: RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous))
                }
                Button(action: onLogEdit) {
                    Text(item.isSeriesEligible ? "Log & edit" : "Duplicate & edit")
                        .font(Baron.heading(11.5))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Baron.neutral700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                            .strokeBorder(Baron.neutral300, lineWidth: 1))
                }
                Button(action: onOpenThing) {
                    Text(item.assetName.split(separator: " ").first.map(String.init) ?? item.assetName)
                        .font(Baron.heading(11.5))
                        .tracking(0.6)
                        .foregroundStyle(Baron.accent800)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                            .strokeBorder(Baron.neutral300, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(alignment: .leading) {
            // Left status edge: the card's own fill plus a 3pt colored strip, clipped together
            // so the strip follows the corner radius.
            ZStack(alignment: .leading) {
                Baron.surface
                edgeColor.frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: Baron.Radius.card, style: .continuous))
        }
        .baronShadow(.medium)
    }
}

// MARK: - History row

private struct HistoryDisplay: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let amount: Decimal?
    let isMoney: Bool
    let target: HistoryTarget
}

private enum HistoryTarget {
    case asset(UUID, DetailAnchor?)
    case event(UUID, UUID)
    case transaction(UUID, UUID)
}

private struct HistoryRowView: View {
    let display: HistoryDisplay
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Text(display.isMoney ? "$" : "◷")
                    .font(Baron.heading(11))
                    .foregroundStyle(display.isMoney ? Baron.accent800 : Baron.neutral700)
                    .frame(width: 28, height: 28)
                    .background(display.isMoney ? Baron.accent100 : Baron.neutral200,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(display.title)
                        .font(Baron.body(14, .medium))
                        .foregroundStyle(Baron.text)
                        .lineLimit(1)
                    Text(display.subtitle)
                        .font(Baron.body(12))
                        .foregroundStyle(Baron.neutral600)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let amount = display.amount {
                    Text(TimelineTab.money(amount))
                        .font(Baron.body(13, .medium))
                        .foregroundStyle(amount < 0 ? Baron.danger : Baron.good)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .baronCard(radius: Baron.Radius.field, elevation: .low)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared sheet items

private struct PushedAsset: Identifiable, Hashable {
    let id: UUID
    let section: DetailAnchor?
}

private struct AddTarget: Identifiable {
    let assetID: UUID
    let assetName: String
    var id: UUID { assetID }
}

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
