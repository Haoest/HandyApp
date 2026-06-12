import SwiftUI

/// Home screen: the creation history from `AssetStore.activityLog`, grouped by day,
/// rendered as sentences with inline hot links. Links use a private `handylog://`
/// URL scheme intercepted by an OpenURLAction, so a single Text can hold several
/// tap targets that wrap naturally. Names are resolved live from the store; records
/// that no longer resolve (deleted) degrade to plain, unlinked text.
struct HomeTab: View {
    @Environment(AssetStore.self) private var store
    @State private var pushedAssetID: UUID?
    @State private var eventToEdit: ResolvedEvent?
    @State private var transactionToEdit: ResolvedTransaction?

    private var dayGroups: [(day: Date, entries: [ActivityLogEntry])] {
        Dictionary(grouping: store.activityLog) { Calendar.current.startOfDay(for: $0.timestamp) }
            .map { (day: $0.key, entries: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.activityLog.isEmpty {
                    ContentUnavailableView(
                        "No Activity",
                        systemImage: "waveform",
                        description: Text("Created assets, events, and transactions will show up here.")
                    )
                } else {
                    List {
                        ForEach(dayGroups, id: \.day) { group in
                            Section(Self.dayFormatter.string(from: group.day)) {
                                ForEach(group.entries) { entry in
                                    Text(sentence(for: entry))
                                        .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .environment(\.openURL, OpenURLAction { handleLink($0) })
                }
            }
            .navigationTitle("Home")
            .navigationDestination(item: $pushedAssetID) { id in
                if let asset = store.assets[id], !asset.isDeleted {
                    AssetDetailView(asset: asset)
                } else {
                    ContentUnavailableView(
                        "Asset Not Found",
                        systemImage: "shippingbox",
                        description: Text("This asset no longer exists.")
                    )
                }
            }
            .sheet(item: $eventToEdit) { resolved in
                EventEditView(existing: resolved.event) { title, date, notes, recurrence in
                    try? store.updateEvent(id: resolved.event.id, onAssetID: resolved.assetID, title: title, date: date, notes: notes, recurrence: recurrence)
                }
            }
            .sheet(item: $transactionToEdit) { resolved in
                TransactionEditView(existing: resolved.transaction) { details, amount, date, kind, payeeID, notes, recurrence in
                    try? store.updateTransaction(id: resolved.transaction.id, onAssetID: resolved.assetID, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence)
                }
            }
        }
    }

    // MARK: - Sentence building

    private func sentence(for entry: ActivityLogEntry) -> AttributedString {
        switch entry.kind {
        case .asset:
            let asset = liveAsset(entry.recordID)
            let time = entry.timestamp.formatted(date: .omitted, time: .shortened)
            return plain("Asset ")
                + linked(asset?.name ?? "(deleted)", to: asset.flatMap { assetURL($0.id) })
                + plain(" created at \(time)")

        case .event:
            let asset = entry.owningAssetID.flatMap(liveAsset)
            let event = asset?.events.first { $0.id == entry.recordID }
            let time = entry.timestamp.formatted(date: .omitted, time: .shortened)
            return plain("Event ")
                + linked(event?.title ?? "(deleted)", to: zip2(asset, event).flatMap { recordURL("event", $0.id, $1.id) })
                + plain(" logged to ")
                + linked(asset?.name ?? "(deleted)", to: asset.flatMap { assetURL($0.id) })
                + plain(" at \(time)")

        case .transaction:
            let asset = entry.owningAssetID.flatMap(liveAsset)
            let txn = asset?.transactions.first { $0.id == entry.recordID }
            let assetPart = linked(asset?.name ?? "(deleted)", to: asset.flatMap { assetURL($0.id) })
            let time = entry.timestamp.formatted(date: .omitted, time: .shortened)
            guard let txn else {
                return plain("Transaction logged to ") + assetPart + plain(" (deleted) at \(time)")
            }
            let amount = txn.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
            return plain("\(txn.kind.rawValue) transaction logged to ")
                + assetPart
                + plain(" with amount ")
                + linked(amount, to: zip2(asset, txn).flatMap { recordURL("transaction", $0.id, $1.id) })
                + plain(" at \(time)")
        }
    }

    private func liveAsset(_ id: UUID) -> Asset? {
        guard let asset = store.assets[id], !asset.isDeleted else { return nil }
        return asset
    }

    private func plain(_ text: String) -> AttributedString {
        AttributedString(text)
    }

    private func linked(_ text: String, to url: URL?) -> AttributedString {
        var part = AttributedString(text)
        if let url {
            part.link = url
            part.foregroundColor = .accentColor
        } else {
            part.foregroundColor = .secondary
        }
        return part
    }

    private func assetURL(_ id: UUID) -> URL? {
        URL(string: "handylog://asset/\(id.uuidString)")
    }

    private func recordURL(_ kind: String, _ assetID: UUID, _ recordID: UUID) -> URL? {
        URL(string: "handylog://\(kind)/\(assetID.uuidString)/\(recordID.uuidString)")
    }

    /// `zip` for optionals: non-nil only when both are.
    private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    // MARK: - Link handling

    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "handylog" else { return .systemAction }
        let ids = url.pathComponents.filter { $0 != "/" }.compactMap(UUID.init(uuidString:))
        switch url.host() {
        case "asset":
            if let assetID = ids.first { pushedAssetID = assetID }
        case "event":
            if ids.count == 2, let asset = liveAsset(ids[0]),
               let event = asset.events.first(where: { $0.id == ids[1] }) {
                eventToEdit = ResolvedEvent(event: event, assetID: asset.id)
            }
        case "transaction":
            if ids.count == 2, let asset = liveAsset(ids[0]),
               let txn = asset.transactions.first(where: { $0.id == ids[1] }) {
                transactionToEdit = ResolvedTransaction(transaction: txn, assetID: asset.id)
            }
        default:
            break
        }
        return .handled
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

/// Sheet items pairing a record with its owning asset id, needed by the store's
/// update methods when saving from the edit sheets.
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
