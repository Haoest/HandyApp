import SwiftUI

/// The Things tab — the redesign's replacement for the Assets list.
///
/// The old All/Tree segmented control is gone: the design browses by search plus category
/// filter chips, and reaches nested things through a parent's "Inside" tab rather than an
/// expandable outline. Each row carries the roll-ups from `ThingsDigest` (next due, trailing
/// 12-month net, record count) and a "+" that opens the shared quick-log kind picker.
struct ThingsTab: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var query = ""
    @State private var categoryFilter: UUID?

    @State private var newAssetPresented = false
    @State private var paywallPresented = false
    @State private var paywallReason: PaywallReason = .assets
    @State private var pendingAssetName: String?
    @State private var createdAssetID: UUID?

    @State private var quickLogStep: QuickLogStep?
    @State private var addEventTarget: AddTarget?
    @State private var addTransactionTarget: AddTarget?

    // MARK: - Derived state

    private var matches: [Asset] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.allAssets
            .filter { asset in
                guard categoryFilter == nil || asset.category.id == categoryFilter else { return false }
                guard !trimmed.isEmpty else { return true }
                if asset.name.lowercased().contains(trimmed) { return true }
                if asset.category.name.lowercased().contains(trimmed) { return true }
                return spec(for: asset).lowercased().contains(trimmed)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// "All" plus every category that currently holds at least one thing — see
    /// `CategoryFilterChip.chips`, shared with the quick-log thing picker.
    private var filterChips: [CategoryFilterChip] { CategoryFilterChip.chips(for: store.allAssets) }

    private var orderedAssetIDs: [UUID] { matches.map(\.id) }

    // MARK: - Body

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ZStack {
                Baron.background.ignoresSafeArea()
                if store.allAssets.isEmpty {
                    ContentUnavailableView(
                        "No things yet",
                        systemImage: "shippingbox",
                        description: Text("Tap + New to add the first thing you own.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            searchField.padding(.top, 15)
                            filterRow.padding(.top, 12)
                            rows.padding(.top, 16)
                        }
                        .padding(.horizontal, Baron.pageInset)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $router.pendingAssetID) { id in
                if let asset = store.assets[id], !asset.isDeleted, !asset.isPurged {
                    ThingDetailView(asset: asset, orderedIDs: orderedAssetIDs, initialAnchor: router.pendingAssetAnchor)
                        .onAppear { router.pendingAssetAnchor = nil }
                } else {
                    ContentUnavailableView("Thing Not Found", systemImage: "shippingbox",
                                           description: Text("This thing no longer exists."))
                }
            }
            .sheet(isPresented: $newAssetPresented, onDismiss: {
                pendingAssetName = nil
                // Push after the sheet has finished dismissing — pushing onto the
                // NavigationStack mid-animation can be dropped by SwiftUI.
                if let id = createdAssetID {
                    createdAssetID = nil
                    router.pendingAssetID = id
                }
            }) {
                NewAssetSheet(initialName: pendingAssetName) { asset in
                    createdAssetID = asset.id
                    newAssetPresented = false
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
            .sheet(isPresented: $paywallPresented) { PaywallView(reason: paywallReason) }
            .onAppear {
                consumeFocusedCategory()
                consumePendingNewAsset()
            }
            .onChange(of: router.pendingNewAsset) { _, pending in
                if pending { consumePendingNewAsset() }
            }
            .onChange(of: router.focusedCategoryID) { _, id in
                if id != nil { consumeFocusedCategory() }
            }
        }
    }

    // MARK: - Header and controls

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text("Things")
                .font(Baron.heading(32))
                .foregroundStyle(Baron.text)
            Spacer(minLength: 0)
            Button {
                if store.hasAssetCapacity { newAssetPresented = true } else { present(.assets) }
            } label: {
                Text("+ New")
                    .font(Baron.heading(12.5))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(Baron.fill, in: RoundedRectangle(cornerRadius: Baron.Radius.field, style: .continuous))
            }
            .baronShadow(.high)
            .accessibilityIdentifier("newAssetButton")
        }
        .padding(.top, 12)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(Baron.neutral500)
            TextField("Search things, specs, categories", text: $query)
                .font(Baron.body(14))
                .foregroundStyle(Baron.text)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Baron.neutral400)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .baronCard(radius: 15, elevation: .low)
    }

    private var filterRow: some View {
        CategoryFilterChips(chips: filterChips, selection: $categoryFilter)
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        if matches.isEmpty {
            VStack(spacing: 6) {
                Text("Nothing matches")
                    .font(Baron.heading(18))
                    .foregroundStyle(Baron.text)
                Text("Clear the search or pick another category.")
                    .font(Baron.body(13))
                    .foregroundStyle(Baron.neutral600)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .baronCard(elevation: .low)
        } else {
            VStack(spacing: 10) {
                ForEach(matches) { asset in
                    ThingRow(
                        asset: asset,
                        spec: spec(for: asset),
                        facts: facts(for: asset),
                        onOpen: { router.pendingAssetID = asset.id },
                        onQuickAdd: { quickLogStep = .pickKind(assetID: asset.id) }
                    )
                }
            }
        }
    }

    // MARK: - Facts

    private func facts(for asset: Asset) -> ThingFacts {
        ThingsDigest.facts(
            events: asset.liveEvents,
            transactions: asset.liveTransactions,
            transactionAmounts: asset.liveTransactions.map {
                (date: $0.date, signedAmount: $0.kind == .expense ? -$0.amount : $0.amount)
            }
        )
    }

    private func spec(for asset: Asset) -> String {
        ThingsDigest.spec(from: (asset.baseProperties + asset.customProperties).compactMap(\.value))
    }

    // MARK: - Actions

    private func startRecord(assetID: UUID, isEvent: Bool) {
        guard let asset = store.assets[assetID], !asset.isDeleted, !asset.isPurged else { return }
        guard store.hasRecordCapacity(for: asset) else { return present(.records) }
        if isEvent {
            addEventTarget = AddTarget(assetID: asset.id, assetName: asset.name)
        } else {
            addTransactionTarget = AddTarget(assetID: asset.id, assetName: asset.name)
        }
    }

    private func present(_ reason: PaywallReason) {
        paywallReason = reason
        paywallPresented = true
    }

    /// The Categories tab's "Assets" quick action used to scroll to a section and flash it.
    /// With the redesign's chips there is a better answer: select that category's filter.
    private func consumeFocusedCategory() {
        guard let id = router.focusedCategoryID else { return }
        categoryFilter = id
        query = ""
        router.focusedCategoryID = nil
    }

    private func consumePendingNewAsset() {
        guard router.pendingNewAsset else { return }
        router.pendingNewAsset = false
        pendingAssetName = router.pendingNewAssetName
        router.pendingNewAssetName = nil
        if store.hasAssetCapacity { newAssetPresented = true } else { present(.assets) }
    }
}

// MARK: - Row

private struct ThingRow: View {
    let asset: Asset
    let spec: String
    let facts: ThingFacts
    let onOpen: () -> Void
    let onQuickAdd: () -> Void

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .appPreferred
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(spacing: 3) {
                    Image(systemName: asset.category.iconName)
                        .font(.system(size: 21, weight: .light))
                    Text(asset.category.name)
                        .font(Baron.heading(8.5))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .opacity(0.75)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 3)
                }
                .foregroundStyle(Baron.accent800)
                .frame(width: 58, height: 58)
                .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(asset.name)
                            .font(Baron.heading(17))
                            .foregroundStyle(Baron.text)
                            .lineLimit(1)
                        if facts.isLate {
                            Text("Late")
                                .font(Baron.body(9.5, .semibold))
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(Baron.danger)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Baron.dangerBackground, in: Capsule())
                        }
                    }
                    if !spec.isEmpty {
                        Text(spec)
                            .font(Baron.body(12.5))
                            .foregroundStyle(Baron.neutral600)
                            .lineLimit(1)
                    }
                    HStack(spacing: 14) {
                        stat("Next", value: facts.nextDue.map { Self.dueFormatter.string(from: $0) } ?? "—",
                             color: facts.isLate ? Baron.danger : Baron.text)
                        stat("12 mo", value: TimelineTab.money(facts.netLast12Months), color: Baron.text)
                        stat("Records", value: "\(facts.recordCount)", color: Baron.text)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onQuickAdd) {
                Image(systemName: "plus")
                    .font(Baron.heading(15))
                    .foregroundStyle(Baron.accent800)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                        .strokeBorder(Baron.neutral300, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .baronCard()
    }

    private func stat(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Baron.body(11.5))
                .foregroundStyle(Baron.neutral600)
            Text(value)
                .font(Baron.body(11.5, .semibold))
                .foregroundStyle(color)
        }
        .lineLimit(1)
    }
}

// MARK: - Sheet items

private struct AddTarget: Identifiable {
    let assetID: UUID
    let assetName: String
    var id: UUID { assetID }
}
