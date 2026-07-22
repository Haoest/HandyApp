import SwiftUI
import PhotosUI

/// Jump targets for the section index on the trailing edge of the detail form, and
/// for deep links from the activity log that open straight to a section.
enum DetailAnchor: String, CaseIterable {
    case category = "Category"
    case custom = "Custom"
    case photos = "Photos"
    case events = "Events"
    case transactions = "Transactions"
    case relationship = "Relationship"
    case contents = "What's Inside"
}

extension DetailAnchor {
    var localizedName: LocalizedStringKey { LocalizedStringKey(rawValue) }
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
    /// Frames of the form's content rows; a drag starting inside one of these is left to
    /// that element (its own swipe-to-delete, scroll, or nothing), not used for paging.
    @State private var swipeableRows = SwipeableRowRegistry()

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
        GeometryReader { geo in
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
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(x: dragOffset)
            .environment(swipeableRows)
            // simultaneousGesture so the Form keeps scrolling and tapping; we only claim
            // the gesture for paging once a drag is clearly horizontal and long enough.
            .simultaneousGesture(pagingGesture(width: geo.size.width))
        }
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
                guard !startsOnSwipeableRow(value) else { return }
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
                guard !startsOnSwipeableRow(value) else { return }
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

    /// True when the drag began inside a content row, in which case paging must stand
    /// down and let that element consume (or ignore) the gesture.
    private func startsOnSwipeableRow(_ value: DragGesture.Value) -> Bool {
        swipeableRows.contains(value.startLocation)
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
        slideEdge = .leading
        withAnimation(.easeInOut(duration: 0.28)) { currentID = orderedIDs[i - 1] }
    }

    /// Swipe left → next item; screens scroll right-to-left (new enters from the right).
    private func goToNext() {
        guard hasNext, let i = anchorIndex else { return }
        slideEdge = .trailing
        withAnimation(.easeInOut(duration: 0.28)) { currentID = orderedIDs[i + 1] }
    }
}

private struct AssetDetailContent: View {
    @Environment(AssetStore.self) private var store
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

    private var sortedBase: [AssetProperty] {
        asset.baseProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedCustom: [AssetProperty] {
        _ = asset.modifiedDate
        return asset.customProperties.sorted { $0.sortOrder < $1.sortOrder }
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
            case .contents: return childCount > 0
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
                    }
                } header: {
                    HStack {
                        Text("Custom Field")
                        Spacer()
                        Button { addPropertyPresented = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .id(DetailAnchor.custom)
                PhotosSection(asset: asset, selectedPhoto: $selectedPhoto)
                    .id(DetailAnchor.photos)
                EventsSection(asset: asset, sheetMode: $eventSheetMode, onLimitReached: {
                    paywallReason = .events
                    paywallPresented = true
                })
                    .id(DetailAnchor.events)
                TransactionsSection(asset: asset, sheetMode: $transactionSheetMode, onLimitReached: {
                    paywallReason = .transactions
                    paywallPresented = true
                })
                    .id(DetailAnchor.transactions)
                Section("Relationship") {
                    BelongsToRow(asset: asset)
                        .pagingExcludedRow(id: "relationship")
                }
                .id(DetailAnchor.relationship)
                if !sortedChildren.isEmpty {
                    Section("What's Inside") {
                        ForEach(sortedChildren) { child in
                            NavigationLink(destination: AssetDetailView(asset: child, orderedIDs: sortedChildren.map(\.id))) {
                                Label(child.name, systemImage: child.category.iconName)
                            }
                            .pagingExcludedRow(id: child.id.uuidString)
                        }
                    }
                    .id(DetailAnchor.contents)
                }
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
                } label: {
                    Image(systemName: "plus")
                }
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
            EventEditView { title, date, notes, recurrence in
                try? store.addEvent(title: title, date: date, notes: notes, recurrence: recurrence, toAssetID: asset.id)
            }
        }
        .sheet(isPresented: $addTransactionPresented) {
            TransactionEditView { details, amount, date, kind, payeeID, notes, recurrence in
                try? store.addTransaction(details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, toAssetID: asset.id)
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
        .sheet(item: $eventSheetMode) { mode in
            switch mode {
            case .edit(let event):
                EventEditView(existing: event) { title, date, notes, recurrence in
                    try? store.updateEvent(id: event.id, onAssetID: asset.id, title: title, date: date, notes: notes, recurrence: recurrence)
                }
            case .duplicate(let source):
                EventEditView(prefill: source) { title, date, notes, recurrence in
                    try? store.addEvent(title: title, date: date, notes: notes, recurrence: recurrence, toAssetID: asset.id)
                }
            }
        }
        .sheet(item: $transactionSheetMode) { mode in
            switch mode {
            case .edit(let txn):
                TransactionEditView(existing: txn) { details, amount, date, kind, payeeID, notes, recurrence in
                    try? store.updateTransaction(id: txn.id, onAssetID: asset.id, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence)
                }
            case .duplicate(let source):
                TransactionEditView(prefill: source) { details, amount, date, kind, payeeID, notes, recurrence in
                    try? store.addTransaction(details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, toAssetID: asset.id)
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoViewerSheet(asset: asset, photo: photo)
        }
        .sheet(item: $customPropertyToEdit) { prop in
            PropertyEditView(existing: prop) { definition, value in
                try? store.updateCustomProperty(id: prop.id, onAssetID: asset.id, name: definition.name, type: definition.type)
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
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { text = asset.name; return }
        guard trimmed != asset.name else { return }
        try? store.updateAsset(id: asset.id, name: trimmed)
    }
}
