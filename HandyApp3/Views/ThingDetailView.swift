import SwiftUI
import PhotosUI
import UIKit

/// The four sub-screens of Thing detail. Replaces the old detail form's eight stacked sections
/// and its scroll-to-anchor jump menu — the original UI audit called that form out as "very
/// long, unstructured … no visual hierarchy beyond section headers".
enum ThingSubTab: String, CaseIterable, Identifiable {
    case specs, log, photos, inside
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .specs: return "Specs"
        case .log: return "Log"
        case .photos: return "Photos"
        case .inside: return "Inside"
        }
    }

    /// Where a deep link from the activity log lands. The old anchors were finer-grained than
    /// the four tabs, so several map onto one.
    init(anchor: DetailAnchor) {
        switch anchor {
        case .category, .custom: self = .specs
        case .photos: self = .photos
        case .events, .transactions: self = .log
        case .relationship, .contents: self = .inside
        }
    }
}

/// Thing detail. Paging between siblings is now explicit prev/next buttons at the foot of the
/// screen rather than the old invisible horizontal swipe — the audit flagged that gesture as
/// having "no chrome hinting it exists", and the swipe also fought every row that had its own
/// swipe actions.
struct ThingDetailView: View {
    @Environment(AssetStore.self) private var store
    let orderedIDs: [UUID]
    @State private var currentID: UUID
    @State private var subTab: ThingSubTab

    init(asset: Asset, orderedIDs: [UUID] = [], initialAnchor: DetailAnchor? = nil) {
        self.orderedIDs = orderedIDs
        _currentID = State(initialValue: asset.id)
        _subTab = State(initialValue: initialAnchor.map(ThingSubTab.init(anchor:)) ?? .specs)
    }

    /// Position in the paging sequence. When the current thing isn't itself in the sequence —
    /// a child opened from its parent's Inside tab, say — we anchor to the nearest ancestor
    /// that is, so prev/next still move between siblings at the level the list was showing.
    private var anchorIndex: Int? {
        guard !orderedIDs.isEmpty else { return nil }
        if let index = orderedIDs.firstIndex(of: currentID) { return index }
        guard let asset = store.assets[currentID] else { return nil }
        for ancestor in asset.ancestors {
            if let index = orderedIDs.firstIndex(of: ancestor.id) { return index }
        }
        return nil
    }

    private var previousID: UUID? {
        guard let index = anchorIndex, index > 0 else { return nil }
        return orderedIDs[index - 1]
    }

    private var nextID: UUID? {
        guard let index = anchorIndex, index + 1 < orderedIDs.count else { return nil }
        return orderedIDs[index + 1]
    }

    var body: some View {
        ZStack {
            Baron.background.ignoresSafeArea()
            if let asset = store.assets[currentID], !asset.isDeleted, !asset.isPurged {
                ThingDetailContent(
                    asset: asset,
                    subTab: $subTab,
                    position: anchorIndex.map { ($0 + 1, orderedIDs.count) },
                    previousName: previousID.flatMap { store.assets[$0]?.name },
                    nextName: nextID.flatMap { store.assets[$0]?.name },
                    onPrevious: previousID.map { id in { currentID = id } },
                    onNext: nextID.map { id in { currentID = id } }
                )
                .id(currentID)
            } else {
                ContentUnavailableView(
                    "Thing Not Found",
                    systemImage: "shippingbox",
                    description: Text("This thing no longer exists.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Content

private struct ThingDetailContent: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let asset: Asset
    @Binding var subTab: ThingSubTab
    let position: (index: Int, total: Int)?
    let previousName: String?
    let nextName: String?
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?

    @State private var expandedPropertyID: UUID?
    @State private var renamePresented = false

    // Specs
    @State private var addPropertyPresented = false
    @State private var customPropertyToEdit: AssetProperty?
    @State private var deleteConfirmationPresented = false

    // Log. All sheets are presented from the screen root, not from a row: a row-level sheet is
    // torn down when the list re-evaluates during the first present, which dismisses it
    // immediately. Carried over from the old detail form, where the same trap was documented.
    @State private var addEventPresented = false
    @State private var addTransactionPresented = false
    @State private var initialTransactionKind: TransactionKind?
    @State private var eventSheetMode: EventSheetMode?
    @State private var transactionSheetMode: TransactionSheetMode?
    @State private var seriesHistory: SeriesHistoryRequest?

    // Photos
    @State private var photoSourceDialogPresented = false
    @State private var photoLibraryItem: PhotosPickerItem?
    @State private var photoLibraryPresented = false
    @State private var cameraPresented = false
    @State private var selectedPhoto: Photo?

    // Inside
    @State private var addChildPresented = false
    @State private var createdChildID: UUID?
    @State private var childToOpen: UUID?

    @State private var paywallPresented = false
    @State private var paywallReason: PaywallReason = .assets

    // MARK: - Derived

    private var sortedBase: [AssetProperty] {
        // `isDeleted` lives on the child AssetProperty, not on `asset`, so a tombstone flip
        // alone doesn't invalidate a view keyed only on the array — read `modifiedDate`
        // (bumped alongside every base-property tombstone) so the row actually disappears.
        _ = asset.modifiedDate
        return asset.liveBaseProperties.sorted(by: SortOrdering.precedes)
    }

    private var sortedCustom: [AssetProperty] {
        _ = asset.modifiedDate
        return asset.liveCustomProperties.sorted(by: SortOrdering.precedes)
    }

    private var sortedChildren: [Asset] {
        asset.children
            .filter { !$0.isDeleted && !$0.isPurged }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var facts: ThingFacts {
        ThingsDigest.facts(
            events: asset.liveEvents,
            transactions: asset.liveTransactions,
            transactionAmounts: asset.liveTransactions.map {
                (date: $0.date, signedAmount: $0.kind == .expense ? -$0.amount : $0.amount)
            }
        )
    }

    private var logRows: [ThingLogRow] {
        ThingLogDigest.rows(events: asset.liveEvents, transactions: asset.liveTransactions)
    }

    private func count(for tab: ThingSubTab) -> Int {
        switch tab {
        case .specs: return sortedBase.count + sortedCustom.count
        case .log: return asset.liveEvents.count + asset.liveTransactions.count
        case .photos: return asset.livePhotos.count
        case .inside: return sortedChildren.count
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                identity.padding(.top, 16)
                figures.padding(.top, 14)
                primaryActions.padding(.top, 14)
                subNav.padding(.top, 18)
                Group {
                    switch subTab {
                    case .specs: specsTab
                    case .log: logTab
                    case .photos: photosTab
                    case .inside: insideTab
                    }
                }
                .padding(.top, 14)
                pager.padding(.top, 20)
            }
            .padding(.horizontal, Baron.pageInset)
            .padding(.bottom, 28)
        }
        .modifier(ThingDetailSheets(
            asset: asset,
            addPropertyPresented: $addPropertyPresented,
            customPropertyToEdit: $customPropertyToEdit,
            renamePresented: $renamePresented,
            addEventPresented: $addEventPresented,
            addTransactionPresented: $addTransactionPresented,
            initialTransactionKind: $initialTransactionKind,
            eventSheetMode: $eventSheetMode,
            transactionSheetMode: $transactionSheetMode,
            seriesHistory: $seriesHistory,
            photoSourceDialogPresented: $photoSourceDialogPresented,
            photoLibraryItem: $photoLibraryItem,
            photoLibraryPresented: $photoLibraryPresented,
            cameraPresented: $cameraPresented,
            selectedPhoto: $selectedPhoto,
            addChildPresented: $addChildPresented,
            createdChildID: $createdChildID,
            childToOpen: $childToOpen,
            paywallPresented: $paywallPresented,
            paywallReason: paywallReason,
            deleteConfirmationPresented: $deleteConfirmationPresented,
            childCount: sortedChildren.count,
            siblingIDs: sortedChildren.map(\.id),
            onDelete: {
                try? store.softDeleteAsset(id: asset.id)
                dismiss()
            }
        ))
        .onAppear { consumePendingTransactionKind() }
        .onChange(of: router.pendingTransactionKind) { _, kind in
            if kind != nil { consumePendingTransactionKind() }
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(Baron.heading(15))
                    .foregroundStyle(Baron.accent800)
                    .frame(width: 36, height: 36)
                    .background(Baron.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Baron.neutral300, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if let position {
                Text("\(position.index) of \(position.total)")
                    .font(Baron.body(11.5, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
        }
        .padding(.top, 8)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: asset.category.iconName)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Baron.accent800)
                    .frame(width: 76, height: 76)
                    .background(Baron.accent100, in: RoundedRectangle(cornerRadius: Baron.Radius.card, style: .continuous))
                    .baronShadow(.medium)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text(asset.category.name)
                            .font(Baron.body(10.5, .medium))
                            .tracking(0.55)
                            .foregroundStyle(Baron.accent800)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Baron.accent100, in: Capsule())
                        if let parent = asset.parent, !parent.isDeleted {
                            Button { router.pendingAssetID = parent.id } label: {
                                Text("in \(parent.name)")
                                    .font(Baron.body(10.5, .medium))
                                    .tracking(0.55)
                                    .foregroundStyle(Baron.neutral700)
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .overlay(Capsule().strokeBorder(Baron.neutral300, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { renamePresented = true } label: {
                        Text(asset.name)
                            .font(Baron.heading(25))
                            .foregroundStyle(Baron.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            let spec = ThingsDigest.spec(from: (asset.baseProperties + asset.customProperties).compactMap(\.value))
            if !spec.isEmpty {
                Text(spec)
                    .font(Baron.body(13))
                    .foregroundStyle(Baron.neutral600)
            }
        }
    }

    private var figures: some View {
        let facts = facts
        return HStack(spacing: 9) {
            figure("Next due",
                   value: facts.nextDue.map { Self.dayFormatter.string(from: $0) } ?? "—",
                   color: facts.isLate ? Baron.danger : Baron.text)
            figure("Cost 12 mo", value: TimelineTab.money(facts.netLast12Months), color: Baron.text)
            figure("Records", value: "\(facts.recordCount)", color: Baron.text)
        }
    }

    private func figure(_ label: LocalizedStringKey, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(Baron.body(10, .medium))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral500)
                .lineLimit(1)
            Text(value)
                .font(Baron.heading(16))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .baronCard(radius: 15, elevation: .low)
    }

    private var primaryActions: some View {
        HStack(spacing: 8) {
            Button { startTransaction() } label: {
                actionLabel("+ Money", foreground: .white, background: Baron.fill)
            }
            .buttonStyle(.plain)
            Button { startEvent() } label: {
                actionLabel("+ Event", foreground: Baron.accent800, background: Baron.accent100)
            }
            .buttonStyle(.plain)
            Menu {
                Button { photoSourceDialogPresented = true } label: { Label("Photo", systemImage: "photo") }
                Button { startChild() } label: { Label("Thing inside", systemImage: "shippingbox") }
                Button { addPropertyPresented = true } label: { Label("Custom field", systemImage: "text.badge.plus") }
                Button { renamePresented = true } label: { Label("Rename", systemImage: "pencil") }
                Divider()
                Button(role: .destructive) { deleteConfirmationPresented = true } label: {
                    Label("Delete thing", systemImage: "trash")
                }
            } label: {
                Text("•••")
                    .font(Baron.heading(12))
                    .foregroundStyle(Baron.neutral700)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Baron.neutral300, lineWidth: 1))
            }
            .accessibilityIdentifier("addMenuButton")
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(Baron.heading(12))
            .tracking(0.85)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var subNav: some View {
        HStack(spacing: 7) {
            ForEach(ThingSubTab.allCases) { tab in
                let selected = tab == subTab
                Button { subTab = tab } label: {
                    HStack(spacing: 4) {
                        Text(tab.title)
                        Text("\(count(for: tab))").opacity(0.55)
                    }
                    .font(Baron.heading(11.5))
                    .tracking(0.55)
                    .foregroundStyle(selected ? Color.white : Baron.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selected ? Baron.fill : Baron.surface,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Specs

    private var specsTab: some View {
        VStack(spacing: 9) {
            ForEach(sortedBase) { property in
                specRow(property)
            }
            ForEach(sortedCustom) { property in
                specRow(property,
                        onEditLabel: { customPropertyToEdit = property },
                        onDelete: { try? store.removeCustomProperty(id: property.id, fromAssetID: asset.id) })
            }
            if sortedBase.isEmpty && sortedCustom.isEmpty {
                emptyNote("This thing has no fields yet. Add one below, or give its category a template.")
            }
            dashedButton("+ Custom field") { addPropertyPresented = true }
            Button { deleteConfirmationPresented = true } label: {
                Text("Delete thing")
                    .font(Baron.heading(11.5))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Baron.dangerBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func specRow(_ property: AssetProperty,
                         onEditLabel: (() -> Void)? = nil,
                         onDelete: (() -> Void)? = nil) -> some View {
        ThingSpecRow(
            assetID: asset.id,
            property: property,
            isExpanded: expandedPropertyID == property.id,
            onToggle: {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedPropertyID = expandedPropertyID == property.id ? nil : property.id
                }
            },
            onEditLabel: onEditLabel,
            onDelete: onDelete
        )
    }

    // MARK: - Log

    private var logTab: some View {
        VStack(spacing: 10) {
            if logRows.isEmpty {
                emptyNote("Nothing logged yet. Money and events you record show up here.")
            } else {
                ForEach(logRows) { row in
                    ThingLogRowView(
                        row: row,
                        onOpen: { open(row) },
                        onLogNow: { logNow(row) },
                        onHistory: { seriesHistory = SeriesHistoryRequest(recordID: row.id, isEvent: row.isEvent) },
                        onLogAndEdit: { logAndEdit(row) },
                        onDelete: { delete(row) }
                    )
                }
            }
            HStack(spacing: 8) {
                dashedButton("+ Money") { startTransaction() }
                dashedButton("+ Event") { startEvent() }
            }
        }
    }

    // MARK: - Photos

    private var photosTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                ForEach(asset.livePhotos) { photo in
                    Button { selectedPhoto = photo } label: {
                        PhotoThumbnail(photo: photo)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button { photoSourceDialogPresented = true } label: {
                    Text("+ Photo")
                        .font(Baron.heading(11))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Baron.accent800)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Baron.neutral400))
                }
                .buttonStyle(.plain)
            }
            Text("Tap a photo to caption it, or scan a receipt into a money record.")
                .font(Baron.body(12))
                .foregroundStyle(Baron.neutral600)
        }
    }

    // MARK: - Inside

    private var insideTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(sortedChildren) { child in
                Button { childToOpen = child.id } label: {
                    HStack(spacing: 11) {
                        Image(systemName: child.category.iconName)
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(Baron.accent800)
                            .frame(width: 34, height: 34)
                            .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.name)
                                .font(Baron.body(15, .medium))
                                .foregroundStyle(Baron.text)
                                .lineLimit(1)
                            let spec = ThingsDigest.spec(from: (child.baseProperties + child.customProperties).compactMap(\.value))
                            if !spec.isEmpty {
                                Text(spec)
                                    .font(Baron.body(12))
                                    .foregroundStyle(Baron.neutral600)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        let childFacts = ThingsDigest.facts(
                            events: child.liveEvents, transactions: child.liveTransactions,
                            transactionAmounts: []
                        )
                        if let due = childFacts.nextDue {
                            Text(Self.dayFormatter.string(from: due))
                                .font(Baron.body(12, .medium))
                                .foregroundStyle(childFacts.isLate ? Baron.danger : Baron.accent800)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .baronCard(radius: 16, elevation: .low)
                }
                .buttonStyle(.plain)
            }
            Text(sortedChildren.isEmpty
                 ? "Nothing nested inside \(asset.name) yet."
                 : "Deleting \(asset.name) deletes these too.")
                .font(Baron.body(12.5))
                .foregroundStyle(Baron.neutral600)
            dashedButton("+ Add thing inside") { startChild() }
            BelongsToRow(asset: asset)
                .padding(.top, 4)
        }
    }

    // MARK: - Pager

    @ViewBuilder
    private var pager: some View {
        if onPrevious != nil || onNext != nil {
            HStack(spacing: 9) {
                pagerButton(title: previousName.map { "‹ \($0)" }, action: onPrevious)
                pagerButton(title: nextName.map { "\($0) ›" }, action: onNext)
            }
        }
    }

    @ViewBuilder
    private func pagerButton(title: String?, action: (() -> Void)?) -> some View {
        if let title, let action {
            Button(action: action) {
                Text(title)
                    .font(Baron.body(12, .medium))
                    .foregroundStyle(Baron.accent800)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Baron.surface, in: RoundedRectangle(cornerRadius: Baron.Radius.field, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Baron.Radius.field, style: .continuous)
                        .strokeBorder(Baron.neutral300, lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    // MARK: - Shared bits

    private func dashedButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Baron.heading(11.5))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Baron.accent800)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Baron.neutral400))
        }
        .buttonStyle(.plain)
    }

    private func emptyNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Baron.body(13))
            .foregroundStyle(Baron.neutral600)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .baronCard(radius: 16, elevation: .low)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    // MARK: - Actions

    private func startEvent() {
        if store.hasEventCapacity(for: asset) { addEventPresented = true }
        else { present(.events) }
    }

    private func startTransaction() {
        if store.hasTransactionCapacity(for: asset) { addTransactionPresented = true }
        else { present(.transactions) }
    }

    private func startChild() {
        if store.hasAssetCapacity { addChildPresented = true }
        else { present(.assets) }
    }

    private func present(_ reason: PaywallReason) {
        paywallReason = reason
        paywallPresented = true
    }

    private func open(_ row: ThingLogRow) {
        if row.isEvent {
            guard let event = asset.liveEvents.first(where: { $0.id == row.id }) else { return }
            eventSheetMode = .edit(event)
        } else {
            guard let transaction = asset.liveTransactions.first(where: { $0.id == row.id }) else { return }
            transactionSheetMode = .edit(transaction)
        }
    }

    /// Instant duplicate, no sheet — the same "Log Now" the old row context menus offered.
    private func logNow(_ row: ThingLogRow) {
        if row.isEvent {
            guard store.hasEventCapacity(for: asset) else { return present(.events) }
            try? store.duplicateEvent(id: row.id, onAssetID: asset.id)
        } else {
            guard store.hasTransactionCapacity(for: asset) else { return present(.transactions) }
            try? store.duplicateTransaction(id: row.id, onAssetID: asset.id)
        }
    }

    /// Opens a prefilled duplicate for review before saving — the old "Log & Edit".
    private func logAndEdit(_ row: ThingLogRow) {
        if row.isEvent {
            guard store.hasEventCapacity(for: asset) else { return present(.events) }
            guard let event = asset.liveEvents.first(where: { $0.id == row.id }) else { return }
            eventSheetMode = .duplicate(event)
        } else {
            guard store.hasTransactionCapacity(for: asset) else { return present(.transactions) }
            guard let txn = asset.liveTransactions.first(where: { $0.id == row.id }) else { return }
            transactionSheetMode = .duplicate(txn)
        }
    }

    /// Deletes only the represented record. A series' other members stay — matching the old
    /// per-row swipe-to-delete, which never deleted a whole series either.
    private func delete(_ row: ThingLogRow) {
        if row.isEvent {
            try? store.removeEvent(id: row.id, fromAssetID: asset.id)
        } else {
            try? store.removeTransaction(id: row.id, fromAssetID: asset.id)
        }
    }

    private func consumePendingTransactionKind() {
        guard let kind = router.pendingTransactionKind else { return }
        router.pendingTransactionKind = nil
        initialTransactionKind = kind
        subTab = .log
        startTransaction()
    }
}

// MARK: - Log row

private struct ThingLogRowView: View {
    let row: ThingLogRow
    let onOpen: () -> Void
    let onLogNow: () -> Void
    let onHistory: () -> Void
    let onLogAndEdit: () -> Void
    let onDelete: () -> Void

    private var meta: String {
        var parts: [String] = []
        if row.recurs {
            let next = row.dueDate ?? row.date
            parts.append(String(localized: "Next \(ThingDetailContent.dayFormatter.string(from: next))"))
        } else {
            parts.append(String(localized: "One-off · \(ThingDetailContent.dayFormatter.string(from: row.date))"))
        }
        if row.isWatched { parts.append(String(localized: "watched")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    Text(row.isEvent ? "◷" : "$")
                        .font(Baron.heading(12))
                        .foregroundStyle(row.isLate ? Baron.danger : (row.isEvent ? Baron.neutral700 : Baron.accent800))
                        .frame(width: 32, height: 32)
                        .background(row.isLate ? Baron.dangerBackground : (row.isEvent ? Baron.neutral200 : Baron.accent100),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(row.title)
                                .font(Baron.body(14.5, .medium))
                                .foregroundStyle(Baron.text)
                                .lineLimit(1)
                            if let interval = row.interval {
                                Text(interval.abbreviation)
                                    .font(Baron.body(9.5, .medium))
                                    .tracking(0.6)
                                    .foregroundStyle(Baron.accent800)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Baron.accent100, in: Capsule())
                            }
                            if row.isLate {
                                Text("Late")
                                    .font(Baron.body(9.5, .semibold))
                                    .tracking(0.7)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Baron.danger)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Baron.dangerBackground, in: Capsule())
                            }
                        }
                        Text(meta)
                            .font(Baron.body(12))
                            .foregroundStyle(Baron.neutral600)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let amount = row.signedAmount {
                        Text(TimelineTab.money(amount))
                            .font(Baron.body(13.5, .medium))
                            .foregroundStyle(amount < 0 ? Baron.danger : Baron.good)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if row.recurs {
                HStack(spacing: 8) {
                    smallButton("Log now", foreground: Baron.accent800, background: Baron.accent100, bordered: false, action: onLogNow)
                    smallButton("History", foreground: Baron.neutral700, background: Baron.surface, bordered: true, action: onHistory)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 13)
            }
        }
        .baronCard(radius: 16, elevation: .low)
        // Delete and the prefilled "log & edit" duplicate have no room in the design's
        // two-button row. They keep the placement the old list rows used — a long press —
        // rather than being dropped.
        .contextMenu {
            Button {
                onLogAndEdit()
            } label: {
                Label(row.recurs ? "Log & Edit" : "Duplicate & Edit", systemImage: "square.and.pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func smallButton(_ title: LocalizedStringKey, foreground: Color, background: Color, bordered: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Baron.heading(11))
                .tracking(0.75)
                .textCase(.uppercase)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(background, in: RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                    .strokeBorder(bordered ? Baron.neutral300 : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Identifies which record's series history to show. Held as an id rather than the record
/// itself so the sheet always renders against the store's current copy.
private struct SeriesHistoryRequest: Identifiable {
    let recordID: UUID
    let isEvent: Bool
    var id: UUID { recordID }
}

// MARK: - Photo cell

private struct PhotoThumbnail: View {
    let photo: Photo

    var body: some View {
        Group {
            if let image = ThumbnailCache.image(for: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Baron.neutral200
            }
        }
        // A photo synced from a peer arrives before its thumbnail file does; poll briefly
        // rather than showing a permanent gray tile. Same wait the old grid used.
        .task(id: photo.id) {
            guard photo.thumbnailData == nil else { return }
            for _ in 0..<10 {
                if Task.isCancelled { return }
                if let data = PhotoStorage.loadThumb(id: photo.id) {
                    photo.thumbnailData = data
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - Rename

private struct ThingRenameSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    @State private var text: String

    init(asset: Asset) {
        self.asset = asset
        _text = State(initialValue: asset.name)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $text)
                    .limitLength(TextLimits.assetName, text: $text)
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? store.updateAsset(id: asset.id, name: trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || trimmed == asset.name)
                }
            }
        }
    }
}

// MARK: - Sheets

/// Every sheet, dialog, and navigation destination the detail screen owns, lifted into one
/// modifier purely to keep `ThingDetailContent.body` readable. They all have to be attached at
/// the screen root — see the note on the `@State` declarations.
private struct ThingDetailSheets: ViewModifier {
    @Environment(AssetStore.self) private var store

    let asset: Asset
    @Binding var addPropertyPresented: Bool
    @Binding var customPropertyToEdit: AssetProperty?
    @Binding var renamePresented: Bool
    @Binding var addEventPresented: Bool
    @Binding var addTransactionPresented: Bool
    @Binding var initialTransactionKind: TransactionKind?
    @Binding var eventSheetMode: EventSheetMode?
    @Binding var transactionSheetMode: TransactionSheetMode?
    @Binding var seriesHistory: SeriesHistoryRequest?
    @Binding var photoSourceDialogPresented: Bool
    @Binding var photoLibraryItem: PhotosPickerItem?
    @Binding var photoLibraryPresented: Bool
    @Binding var cameraPresented: Bool
    @Binding var selectedPhoto: Photo?
    @Binding var addChildPresented: Bool
    @Binding var createdChildID: UUID?
    @Binding var childToOpen: UUID?
    @Binding var paywallPresented: Bool
    let paywallReason: PaywallReason
    @Binding var deleteConfirmationPresented: Bool
    let childCount: Int
    let siblingIDs: [UUID]
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add Photo", isPresented: $photoSourceDialogPresented) {
                Button("Photo Library") { photoLibraryPresented = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Camera") { cameraPresented = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $photoLibraryPresented, selection: $photoLibraryItem, matching: .images)
            .onChange(of: photoLibraryItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data),
                          let imageData = ImageScaling.imageData(from: uiImage),
                          let thumbData = ImageScaling.thumbnailData(from: uiImage) else { return }
                    try? store.addPhoto(imageData: imageData, thumbnailData: thumbData, toAssetID: asset.id)
                    photoLibraryItem = nil
                }
            }
            .background(
                CameraPicker(isPresented: $cameraPresented) { uiImage in
                    guard let imageData = ImageScaling.imageData(from: uiImage),
                          let thumbData = ImageScaling.thumbnailData(from: uiImage) else { return }
                    try? store.addPhoto(imageData: imageData, thumbnailData: thumbData, toAssetID: asset.id)
                }
            )
            .sheet(isPresented: $renamePresented) { ThingRenameSheet(asset: asset) }
            .sheet(isPresented: $addEventPresented) {
                EventEditView(assetName: asset.name, assetID: asset.id) { title, date, notes, recurrence, due in
                    try? store.addEvent(title: title, date: date, notes: notes, recurrence: recurrence, due: due, toAssetID: asset.id)
                }
            }
            .sheet(isPresented: $addTransactionPresented, onDismiss: { initialTransactionKind = nil }) {
                TransactionEditView(initialKind: initialTransactionKind, assetName: asset.name, assetID: asset.id) { details, amount, date, kind, payeeID, notes, recurrence, due in
                    try? store.addTransaction(details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due, toAssetID: asset.id)
                }
            }
            .sheet(item: $eventSheetMode) { mode in
                switch mode {
                case .edit(let event):
                    EventEditView(existing: event, seriesCount: SeriesLogic.members(of: event, in: asset.liveEvents).count, assetName: asset.name, assetID: asset.id) { title, date, notes, recurrence, due in
                        try? store.updateEvent(id: event.id, onAssetID: asset.id, title: title, date: date, notes: notes, recurrence: recurrence, due: due)
                    }
                case .duplicate(let source):
                    EventEditView(
                        prefill: source,
                        prefillTitle: store.suggestedDuplicateTitle(forEventID: source.id, onAssetID: asset.id),
                        prefillDue: store.suggestedDuplicateDue(forEventID: source.id, onAssetID: asset.id),
                        assetName: asset.name,
                        assetID: asset.id
                    ) { title, date, notes, recurrence, due in
                        try? store.duplicateEvent(id: source.id, onAssetID: asset.id, title: title, date: date, notes: notes, recurrence: recurrence, due: due)
                    }
                }
            }
            .sheet(item: $transactionSheetMode) { mode in
                switch mode {
                case .edit(let txn):
                    TransactionEditView(existing: txn, seriesCount: SeriesLogic.members(of: txn, in: asset.liveTransactions).count, assetName: asset.name, assetID: asset.id) { details, amount, date, kind, payeeID, notes, recurrence, due in
                        try? store.updateTransaction(id: txn.id, onAssetID: asset.id, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due)
                    }
                case .duplicate(let source):
                    TransactionEditView(
                        prefill: source,
                        prefillDetails: store.suggestedDuplicateTitle(forTransactionID: source.id, onAssetID: asset.id),
                        prefillDue: store.suggestedDuplicateDue(forTransactionID: source.id, onAssetID: asset.id),
                        assetName: asset.name,
                        assetID: asset.id
                    ) { details, amount, date, kind, payeeID, notes, recurrence, due in
                        try? store.duplicateTransaction(id: source.id, onAssetID: asset.id, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due)
                    }
                }
            }
            .sheet(item: $seriesHistory) { request in
                if request.isEvent, let event = asset.liveEvents.first(where: { $0.id == request.recordID }) {
                    SeriesOccurrencesSheet(occurrences: LedgerDigest.seriesOccurrences(of: event, in: asset.liveEvents)
                        .map(SeriesOccurrenceDisplay.init(event:)))
                } else if let txn = asset.liveTransactions.first(where: { $0.id == request.recordID }) {
                    SeriesOccurrencesSheet(occurrences: LedgerDigest.seriesOccurrences(of: txn, in: asset.liveTransactions)
                        .map(SeriesOccurrenceDisplay.init(transaction:)))
                }
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoViewerSheet(asset: asset, photo: photo)
            }
            .sheet(isPresented: $addPropertyPresented) {
                PropertyEditView { definition, value in
                    try? store.addCustomProperty(definition: definition, value: value, toAssetID: asset.id)
                }
            }
            .sheet(item: $customPropertyToEdit) { prop in
                PropertyEditView(existing: prop) { definition, value in
                    try? store.updateCustomProperty(id: prop.id, onAssetID: asset.id, name: definition.name, type: definition.type, maxLength: definition.maxLength)
                    if let value {
                        try? store.setPropertyValue(value, forDefinitionID: prop.definition.id, onAssetID: asset.id)
                    } else {
                        try? store.removePropertyValue(forDefinitionID: prop.definition.id, fromAssetID: asset.id)
                    }
                }
            }
            .sheet(isPresented: $addChildPresented, onDismiss: {
                // Push after the sheet has finished dismissing — pushing onto the
                // NavigationStack mid-animation can be dropped by SwiftUI.
                if let id = createdChildID {
                    createdChildID = nil
                    childToOpen = id
                }
            }) {
                NewAssetSheet(initialParentID: asset.id) { newAsset in
                    createdChildID = newAsset.id
                    addChildPresented = false
                }
            }
            .sheet(isPresented: $paywallPresented) { PaywallView(reason: paywallReason) }
            .navigationDestination(item: $childToOpen) { id in
                if let child = store.assets[id], !child.isDeleted, !child.isPurged {
                    ThingDetailView(asset: child, orderedIDs: siblingIDs)
                } else {
                    ContentUnavailableView("Thing Not Found", systemImage: "shippingbox",
                                           description: Text("This thing no longer exists."))
                }
            }
            .confirmationDialog("Delete \"\(asset.name)\"?", isPresented: $deleteConfirmationPresented, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if childCount > 0 {
                    Text("^[\(childCount) item](inflect: true) inside will be deleted too.")
                }
            }
    }
}
