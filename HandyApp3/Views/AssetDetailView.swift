import SwiftUI
import PhotosUI
import UIKit

/// Section header with a trailing add button, e.g. "Photos  +".
struct AddSectionHeader: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) { Image(systemName: "plus") }
        }
    }
}

/// Pages between sibling assets with a horizontal swipe, sliding the detail screen.
/// The sibling order is supplied by the listing screen so it honours its view mode
/// (All vs Tree). Per product spec the gesture is inverted from the usual convention:
/// swipe left → previous item, swipe right → next item.
struct AssetDetailView: View {
    @Environment(AssetStore.self) private var store
    let orderedIDs: [UUID]
    @State private var currentID: UUID
    /// Edge the incoming screen slides in from; flipped per swipe direction.
    /// The outgoing screen slides out the opposite edge, so the pair reads as a scroll.
    @State private var slideEdge: Edge = .trailing
    /// Live horizontal offset used only for the rubber-band bounce at the ends of the
    /// sequence (when there is no asset to page to in the swipe's direction).
    @State private var dragOffset: CGFloat = 0
    /// Vertical bands of the form's content rows; a drag starting inside one of these is left
    /// to that element (its own swipe-to-delete, scroll, or nothing), not used for paging.
    @State private var swipeableRows = SwipeableRowRegistry()
    /// Whether the in-flight drag belongs to a content row, decided once at the drag's
    /// start and held for its whole life. See `suppressesPaging(_:)`.
    @State private var suppressionLatch: SuppressionLatch?
    /// Width of the screen, used only to scale the rubber-band bounce. See `body`.
    @State private var screenWidth: CGFloat = 0

    /// Section to scroll to when first shown — set by deep links from the activity log
    /// (e.g. "Photo added to …" jumps to the Photos section). Applies only to the
    /// initially-shown asset, not to siblings reached by paging.
    let initialAnchor: DetailAnchor?
    private let initialAssetID: UUID

    init(asset: Asset, orderedIDs: [UUID] = [], initialAnchor: DetailAnchor? = nil) {
        self.orderedIDs = orderedIDs
        self.initialAnchor = initialAnchor
        self.initialAssetID = asset.id
        _currentID = State(initialValue: asset.id)
    }

    /// Position of the current asset in the paging sequence. When the current asset is
    /// not itself in the sequence — e.g. a child viewed in Tree mode, where the sequence
    /// is top-level assets — we anchor to its top-most ancestor that is in the sequence,
    /// so paging moves to the adjacent root asset.
    private var anchorIndex: Int? {
        if let i = orderedIDs.firstIndex(of: currentID) { return i }
        var cursor = store.assets[currentID]
        while let asset = cursor {
            if let i = orderedIDs.firstIndex(of: asset.id) { return i }
            cursor = asset.parentID.flatMap { store.assets[$0] }
        }
        return nil
    }
    private var hasPrevious: Bool { (anchorIndex ?? 0) > 0 }
    private var hasNext: Bool {
        guard let i = anchorIndex else { return false }
        return i < orderedIDs.count - 1
    }

    var body: some View {
        ZStack {
            if let asset = store.assets[currentID], !asset.isDeleted {
                AssetDetailContent(asset: asset, scrollTo: currentID == initialAssetID ? initialAnchor : nil)
                    .id(currentID)
                    .transition(slideTransition)
            } else {
                ContentUnavailableView(
                    "Asset Not Found",
                    systemImage: "shippingbox",
                    description: Text("This asset no longer exists.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: dragOffset)
        .environment(swipeableRows)
        // Screen width, for the rubber-band limit only. Read from a background probe rather
        // than by hosting the screen inside a `GeometryReader`: as a container that would
        // re-measure — and re-lay out the entire form beneath it — on every frame of the
        // keyboard's presentation animation, which is exactly when the screen has to stay
        // responsive. It only actually changes on rotation.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { screenWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in screenWidth = width }
            }
        )
        // simultaneousGesture so the Form keeps scrolling and tapping; we only claim
        // the gesture for paging once a drag is clearly horizontal and long enough.
        .simultaneousGesture(pagingGesture(width: screenWidth))
    }

    /// New screen enters from `slideEdge`; old screen exits the opposite edge so the
    /// two move together in one direction (a scroll) rather than overlapping.
    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slideEdge),
            removal: .move(edge: slideEdge == .leading ? .trailing : .leading)
        )
    }

    private func pagingGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .global)
            .onChanged { value in
                // A drag that begins on a content row belongs to that element (its own
                // swipe-to-delete, scroll, or nothing) — only the form's blank areas page.
                guard !suppressesPaging(value) else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                // Only drag-follow when the swipe is clearly horizontal AND there is
                // nothing to page to that way — otherwise leave the Form to scroll and
                // let onEnded commit the page.
                guard abs(dx) > abs(dy) * 1.5, isAtBoundary(forSwipe: dx) else {
                    if dragOffset != 0 { dragOffset = 0 }
                    return
                }
                dragOffset = rubberBand(dx, limit: width / 2)
            }
            .onEnded { value in
                let suppressed = suppressesPaging(value)
                suppressionLatch = nil
                guard !suppressed else { return }
                // A non-zero offset means we were rubber-banding at an end: spring back.
                if dragOffset != 0 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { dragOffset = 0 }
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60 else { return }
                if dx < 0 { goToNext() } else { goToPrevious() }
            }
    }

    /// True when the drag began on a content row, in which case paging must stand down
    /// and let that element consume (or ignore) the gesture.
    ///
    /// The answer is computed once per drag and latched, because the registry is live:
    /// a row being swiped moves, rows can appear or disappear mid-drag, and re-asking on
    /// every `onChanged` let a long swipe-to-delete escape the row it started on and page
    /// the asset. Latching keys off `startLocation`, so a new drag (or one whose `onEnded`
    /// never arrived, e.g. a cancelled gesture) re-decides rather than inheriting.
    private func suppressesPaging(_ value: DragGesture.Value) -> Bool {
        if let latch = suppressionLatch, latch.start == value.startLocation {
            return latch.suppressed
        }
        let suppressed = swipeableRows.contains(value.startLocation)
        suppressionLatch = SuppressionLatch(start: value.startLocation, suppressed: suppressed)
        return suppressed
    }

    /// True when a swipe in `dx`'s direction has no asset to page to (swipe left → next,
    /// swipe right → previous).
    private func isAtBoundary(forSwipe dx: CGFloat) -> Bool {
        (dx < 0 && !hasNext) || (dx > 0 && !hasPrevious)
    }

    /// iOS-style resistive offset: follows the finger with diminishing returns, settling
    /// toward `limit` (half the screen) no matter how far the drag goes.
    private func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let sign: CGFloat = offset < 0 ? -1 : 1
        let distance = abs(offset)
        let resisted = (1 - 1 / (distance / limit * 0.55 + 1)) * limit
        return sign * resisted
    }

    /// Swipe right → previous item; screens scroll left-to-right (new enters from the left).
    private func goToPrevious() {
        guard hasPrevious, let i = anchorIndex else { return }
        // End editing before the subtree swap: the outgoing screen's fields commit on
        // focus loss, and that must happen while their views are still installed rather
        // than racing the .id()-driven teardown.
        endTextEditing()
        slideEdge = .leading
        withAnimation(.easeInOut(duration: 0.28)) { currentID = orderedIDs[i - 1] }
    }

    /// Swipe left → next item; screens scroll right-to-left (new enters from the right).
    private func goToNext() {
        guard hasNext, let i = anchorIndex else { return }
        endTextEditing()
        slideEdge = .trailing
        withAnimation(.easeInOut(duration: 0.28)) { currentID = orderedIDs[i + 1] }
    }
}

private struct AssetDetailContent: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    /// Section to scroll to once the form lays out (deep link from the activity log).
    var scrollTo: DetailAnchor? = nil
    @State private var deleteConfirmationPresented = false
    @State private var addPropertyPresented = false
    @State private var customPropertyToEdit: AssetProperty?

    // Photo add state
    @State private var photoSourceDialogPresented = false
    @State private var photoLibraryItem: PhotosPickerItem?
    @State private var photoLibraryPresented = false
    @State private var cameraPresented = false

    // Event/transaction add state
    @State private var addEventPresented = false
    @State private var addTransactionPresented = false
    @State private var initialTransactionKind: TransactionKind? = nil

    // Paywall presentation. Lives at the Form level (not inside a section/row)
    // for the same reason eventSheetMode/transactionSheetMode/selectedPhoto do.
    @State private var paywallPresented = false
    @State private var paywallReason: PaywallReason = .assets

    // Event/transaction edit & duplicate state. Presented from the Form (not the
    // section) so a row's context menu dismissal can't cancel the first present.
    @State private var eventSheetMode: EventSheetMode?
    @State private var transactionSheetMode: TransactionSheetMode?

    // Photo viewer selection. Presented from the Form (not PhotosSection) for the same
    // reason: a section-level sheet gets torn down when the section body re-evaluates
    // during the first present, dismissing the viewer immediately.
    @State private var selectedPhoto: Photo?

    // New nested asset. Presented from the Form (not a section) for the same reason
    // the photo/event/transaction sheets are.
    @State private var addChildPresented = false
    /// Staged during the sheet, consumed in onDismiss — see the sheet below.
    @State private var createdChildID: UUID?
    /// Drives the push to the newly created child's detail screen.
    @State private var childToOpen: UUID?

    private var sortedBase: [AssetProperty] {
        // `isDeleted` lives on the child AssetProperty, not on `asset` itself, so a tombstone
        // flip alone doesn't invalidate a view keyed only on the array — read `modifiedDate`
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
            .filter { !$0.isDeleted }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var childCount: Int { sortedChildren.count }

    /// Category and Contents anchors only make sense when their sections are rendered.
    private var anchors: [DetailAnchor] {
        DetailAnchor.allCases.filter { anchor in
            switch anchor {
            case .category: return !sortedBase.isEmpty
            default: return true
            }
        }
    }

    private func jumpMenu(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(anchors, id: \.self) { anchor in
                Button { withAnimation { proxy.scrollTo(anchor, anchor: .top) } } label: {
                    Text(anchor.localizedName)
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section("Name") {
                    NameDetailField(asset: asset)
                        .pagingExcludedRow(id: "name")
                }
                if !sortedBase.isEmpty {
                    Section(asset.category.name) {
                        ForEach(sortedBase) { prop in
                            PropertyDetailRow(assetID: asset.id, property: prop)
                                .pagingExcludedRow(id: prop.id.uuidString)
                        }
                        .onMove { fromOffsets, toOffset in
                            try? store.moveBaseProperties(fromOffsets: fromOffsets, toOffset: toOffset, onAssetID: asset.id)
                        }
                    }
                    .id(DetailAnchor.category)
                }
                Section {
                    if sortedCustom.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedCustom) { prop in
                            PropertyDetailRow(assetID: asset.id, property: prop, onEditLabel: { customPropertyToEdit = prop })
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        try? store.removeCustomProperty(id: prop.id, fromAssetID: asset.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .pagingExcludedRow(id: prop.id.uuidString)
                        }
                        .onMove { fromOffsets, toOffset in
                            try? store.moveCustomProperties(fromOffsets: fromOffsets, toOffset: toOffset, onAssetID: asset.id)
                        }
                    }
                } header: {
                    AddSectionHeader(title: "Custom Field") { addPropertyPresented = true }
                }
                .id(DetailAnchor.custom)
                PhotosSection(asset: asset, selectedPhoto: $selectedPhoto, onAdd: {
                    photoSourceDialogPresented = true
                })
                    .id(DetailAnchor.photos)
                EventsSection(asset: asset, sheetMode: $eventSheetMode, onAdd: {
                    if store.hasEventCapacity(for: asset) {
                        addEventPresented = true
                    } else {
                        paywallReason = .events
                        paywallPresented = true
                    }
                }, onLimitReached: {
                    paywallReason = .events
                    paywallPresented = true
                })
                    .id(DetailAnchor.events)
                TransactionsSection(asset: asset, sheetMode: $transactionSheetMode, onAdd: {
                    if store.hasTransactionCapacity(for: asset) {
                        addTransactionPresented = true
                    } else {
                        paywallReason = .transactions
                        paywallPresented = true
                    }
                }, onLimitReached: {
                    paywallReason = .transactions
                    paywallPresented = true
                })
                    .id(DetailAnchor.transactions)
                Section("Relationship") {
                    BelongsToRow(asset: asset)
                        .pagingExcludedRow(id: "relationship")
                }
                .id(DetailAnchor.relationship)
                Section {
                    if sortedChildren.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedChildren) { child in
                            NavigationLink(destination: AssetDetailView(asset: child, orderedIDs: sortedChildren.map(\.id))) {
                                Label(child.name, systemImage: child.category.iconName)
                            }
                            .pagingExcludedRow(id: child.id.uuidString)
                        }
                    }
                } header: {
                    AddSectionHeader(title: "What's Inside") {
                        if store.hasAssetCapacity {
                            addChildPresented = true
                        } else {
                            paywallReason = .assets
                            paywallPresented = true
                        }
                    }
                }
                .id(DetailAnchor.contents)
                Section {
                    Button(role: .destructive) {
                        deleteConfirmationPresented = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Asset")
                            Spacer()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    jumpMenu(proxy)
                }
            }
            .onAppear {
                guard let scrollTo else { return }
                // Defer until the Form has laid its sections out, otherwise the
                // anchor isn't registered with the proxy yet.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo(scrollTo, anchor: .top) }
                }
            }
        }
        .navigationTitle(asset.name)
        .onAppear {
            if let kind = router.pendingTransactionKind {
                router.pendingTransactionKind = nil
                initialTransactionKind = kind
                if store.hasTransactionCapacity(for: asset) { addTransactionPresented = true }
                else { paywallReason = .transactions; paywallPresented = true }
            }
        }
        .onChange(of: router.pendingTransactionKind) { _, kind in
            guard let kind else { return }
            router.pendingTransactionKind = nil
            initialTransactionKind = kind
            if store.hasTransactionCapacity(for: asset) { addTransactionPresented = true }
            else { paywallReason = .transactions; paywallPresented = true }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        photoSourceDialogPresented = true
                    } label: {
                        Label("Photo", systemImage: "photo")
                    }
                    Button {
                        if store.hasEventCapacity(for: asset) {
                            addEventPresented = true
                        } else {
                            paywallReason = .events
                            paywallPresented = true
                        }
                    } label: {
                        Label("Event", systemImage: "calendar")
                    }
                    Button {
                        if store.hasTransactionCapacity(for: asset) {
                            addTransactionPresented = true
                        } else {
                            paywallReason = .transactions
                            paywallPresented = true
                        }
                    } label: {
                        Label("Transaction", systemImage: "dollarsign.circle")
                    }
                    Button {
                        if store.hasAssetCapacity {
                            addChildPresented = true
                        } else {
                            paywallReason = .assets
                            paywallPresented = true
                        }
                    } label: {
                        Label("Add asset inside", systemImage: "shippingbox")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addMenuButton")
            }
        }
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
        .sheet(isPresented: $paywallPresented) {
            PaywallView(reason: paywallReason)
        }
        .sheet(isPresented: $addPropertyPresented) {
            PropertyEditView { definition, value in
                try? store.addCustomProperty(definition: definition, value: value, toAssetID: asset.id)
            }
        }
        .sheet(isPresented: $addChildPresented, onDismiss: {
            // Push after the sheet has finished dismissing — pushing onto the
            // NavigationStack while the sheet is still animating away can be
            // dropped by SwiftUI.
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
        .navigationDestination(item: $childToOpen) { id in
            if let child = store.assets[id], !child.isDeleted {
                AssetDetailView(asset: child, orderedIDs: sortedChildren.map(\.id))
            } else {
                ContentUnavailableView(
                    "Asset Not Found",
                    systemImage: "shippingbox",
                    description: Text("This asset no longer exists.")
                )
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
        .sheet(item: $selectedPhoto) { photo in
            PhotoViewerSheet(asset: asset, photo: photo)
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
        .confirmationDialog("Delete \"\(asset.name)\"?", isPresented: $deleteConfirmationPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? store.softDeleteAsset(id: asset.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if childCount > 0 {
                Text("^[\(childCount) item](inflect: true) inside will be deleted too.")
            }
        }
    }
}

// MARK: - Name field

private struct NameDetailField: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(asset: Asset) {
        self.asset = asset
        _text = State(initialValue: asset.name)
    }

    var body: some View {
        TextField("Name", text: $text)
            .focused($isFocused)
            .onSubmit { commit() }
            .commitsPendingEdit(focused: isFocused) { commit() }
            .limitLength(TextLimits.assetName, text: $text)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { text = asset.name; return }
        guard trimmed != asset.name else { return }
        try? store.updateAsset(id: asset.id, name: trimmed)
    }
}
