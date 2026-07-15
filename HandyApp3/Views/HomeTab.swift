import SwiftUI

/// Home screen: the creation history from `AssetStore.activityLog`, surfaced as the
/// 3 most-recent active days, grouped by item type, with 3+ same-type entries on one
/// asset collapsed into a counted summary line (see `HomeActivityDigest`). Rendered as
/// sentences with inline hot links via a private `handylog://` URL scheme intercepted
/// by an OpenURLAction, so a single Text can hold several tap targets that wrap
/// naturally. Names are resolved live from the store; records that no longer resolve
/// (deleted) degrade to plain, unlinked text.
struct HomeTab: View {
    @Environment(AssetStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @State private var pushedAsset: PushedAsset?
    @State private var eventToEdit: ResolvedEvent?
    @State private var transactionToEdit: ResolvedTransaction?
    @State private var visibleDayCount = HomeActivityDigest.pageSize

    private var days: [HomeDay] {
        HomeActivityDigest.build(from: store.activityLog, dayLimit: visibleDayCount)
    }

    private var hasMoreDays: Bool {
        HomeActivityDigest.activeDayCount(in: store.activityLog) > visibleDayCount
    }

    private var palette: ThemePalette { store.backgroundTheme.palette }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    feed
                        .environment(\.openURL, OpenURLAction { handleLink($0) })
                    versionFooter
                }
                // Background is always the light mist gradient, so pin the scheme
                // light — otherwise the empty state / nav title would flip to light
                // text in system dark mode and lose contrast.
                .environment(\.colorScheme, .light)
            }
            .navigationTitle("Home")
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $pushedAsset) { pushed in
                if let asset = store.assets[pushed.id], !asset.isDeleted {
                    AssetDetailView(asset: asset, initialAnchor: pushed.section)
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

    // MARK: - Contact banner

    private var contactBanner: some View {
        Link(destination: URL(string: "mailto:haoest@gmail.com?subject=handyapp3")!) {
            (Text("Comment, concerns, or questions, ")
                .foregroundStyle(palette.onBackgroundSecondary)
            + Text(verbatim: "email me")
                .underline()
                .foregroundStyle(Color.accentColor))
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    // MARK: - Version footer

    private var versionFooter: some View {
        Text("Application Version: \(Self.appVersion)\(purchases.isFullVersion ? " (F)" : " (T)")")
            .font(.caption2)
            .foregroundStyle(palette.onBackgroundSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: - Feed

    @ViewBuilder
    private var feed: some View {
        if store.activityLog.isEmpty {
            ContentUnavailableView(
                "No Activity",
                systemImage: "waveform",
                description: Text("Created assets, events, and transactions will show up here.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Self.dayFormatter.string(from: group.day))
                                .font(.footnote.weight(.semibold))
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .foregroundStyle(palette.onBackgroundSecondary)
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(group.rows) { row in
                                    Text(line(for: row))
                                        .font(.callout)
                                        .foregroundStyle(palette.onBackground)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if hasMoreDays {
                        moreButton
                    }
                    contactBanner
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var moreButton: some View {
        Button {
            visibleDayCount += HomeActivityDigest.pageSize
        } label: {
            Text("More")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Sentence building

    private func line(for row: HomeRow) -> AttributedString {
        switch row {
        case .single(let entry):
            return sentence(for: entry)
        case .summary(let kind, let assetID, let count, _):
            return summarySentence(kind: kind, assetID: assetID, count: count)
        }
    }

    /// Collapsed line for 3+ same-type entries on one asset, e.g.
    /// "4 transactions added to [Fridge]".
    private func summarySentence(kind: LoggedRecordKind, assetID: UUID, count: Int) -> AttributedString {
        let asset = liveAsset(assetID)
        return plain("\(count) \(typeNoun(kind, count: count)) added to ")
            + linked(asset?.name ?? "(deleted)", to: asset.flatMap { assetURL($0.id, section: anchor(for: kind)) })
    }

    /// The detail-screen section a log entry of this kind should jump to. Asset
    /// creation has no section (opens at the top).
    private func anchor(for kind: LoggedRecordKind) -> DetailAnchor? {
        switch kind {
        case .photo: return .photos
        case .event: return .events
        case .transaction: return .transactions
        case .asset: return nil
        }
    }

    private func typeNoun(_ kind: LoggedRecordKind, count: Int) -> String {
        switch kind {
        case .photo: return count == 1 ? "photo" : "photos"
        case .event: return count == 1 ? "event" : "events"
        case .transaction: return count == 1 ? "transaction" : "transactions"
        case .asset: return count == 1 ? "asset" : "assets"
        }
    }

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
                + linked(asset?.name ?? "(deleted)", to: asset.flatMap { assetURL($0.id, section: .events) })
                + plain(" at \(time)")

        case .transaction:
            let asset = entry.owningAssetID.flatMap(liveAsset)
            let txn = asset?.transactions.first { $0.id == entry.recordID }
            let assetPart = linked(asset?.name ?? "(deleted)", to: asset.flatMap { assetURL($0.id, section: .transactions) })
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

        case .photo:
            let asset = entry.owningAssetID.flatMap(liveAsset)
            let photo = asset?.photos.first { $0.id == entry.recordID }
            let time = entry.timestamp.formatted(date: .omitted, time: .shortened)
            let caption = photo?.caption.trimmingCharacters(in: .whitespaces) ?? ""
            let label = caption.isEmpty ? "Photo" : "Photo “\(caption)”"
            return plain("\(label) added to ")
                + linked(asset?.name ?? "(deleted)", to: asset.flatMap { assetURL($0.id, section: .photos) })
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
            part.foregroundColor = palette.link
        } else {
            part.foregroundColor = palette.deletedText
        }
        return part
    }

    private func assetURL(_ id: UUID, section: DetailAnchor? = nil) -> URL? {
        if let section {
            return URL(string: "handylog://asset/\(id.uuidString)/\(section.rawValue)")
        }
        return URL(string: "handylog://asset/\(id.uuidString)")
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
            if let assetID = ids.first {
                // Trailing non-UUID path component (if any) names the target section.
                let section = url.pathComponents.last.flatMap { DetailAnchor(rawValue: $0) }
                pushedAsset = PushedAsset(id: assetID, section: section)
            }
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

/// Navigation target for an asset link, optionally carrying the section to scroll to.
private struct PushedAsset: Identifiable, Hashable {
    let id: UUID
    let section: DetailAnchor?
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
