import SwiftUI
import Contacts
import PhotosUI

/// Jump targets for the section index on the trailing edge of the detail form.
private enum DetailAnchor: String, CaseIterable {
    case category = "Category"
    case custom = "Custom"
    case photos = "Photos"
    case events = "Events"
    case transactions = "Transactions"
    case relationship = "Relationship"
}

/// Tracks the on-screen (global) frames of content rows so the asset-paging gesture can
/// stand down for drags that start on them: paging is meant to fire only on the form's
/// blank areas (section gaps, headers, empty placeholders), while a swipe that lands on
/// an element — a property, the photo carousel, an event/transaction row — belongs to
/// that element (its own swipe-to-delete, scroll, or nothing) and must not page. Rows
/// write their frames here directly rather than via a `PreferenceKey`, because
/// `List`/`Form` cells don't reliably propagate preferences up to the screen that hosts
/// the paging gesture.
@Observable
final class SwipeableRowRegistry {
    var frames: [String: CGRect] = [:]

    /// True when `point` (in global coordinates) lies inside any registered row.
    func contains(_ point: CGPoint) -> Bool {
        frames.values.contains { $0.contains(point) }
    }
}

private struct PagingExcludedRow: ViewModifier {
    @Environment(SwipeableRowRegistry.self) private var registry
    let id: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { registry.frames[id] = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        registry.frames[id] = frame
                    }
                    .onDisappear { registry.frames[id] = nil }
            }
        )
    }
}

extension View {
    /// Marks a content row that should consume its own swipes instead of paging the asset.
    /// The detail screen reads these frames and suppresses paging for drags that start
    /// inside them, so paging is left to the form's blank areas.
    func pagingExcludedRow(id: String) -> some View {
        modifier(PagingExcludedRow(id: id))
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
    /// Frames of the form's content rows; a drag starting inside one of these is left to
    /// that element (its own swipe-to-delete, scroll, or nothing), not used for paging.
    @State private var swipeableRows = SwipeableRowRegistry()

    init(asset: Asset, orderedIDs: [UUID] = []) {
        self.orderedIDs = orderedIDs
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
                    AssetDetailContent(asset: asset)
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

    // Event/transaction edit & duplicate state. Presented from the Form (not the
    // section) so a row's context menu dismissal can't cancel the first present.
    @State private var eventSheetMode: EventSheetMode?
    @State private var transactionSheetMode: TransactionSheetMode?

    private var sortedBase: [AssetProperty] {
        asset.baseProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedCustom: [AssetProperty] {
        _ = asset.modifiedDate
        return asset.customProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var childCount: Int { asset.children.count }

    /// The category anchor only makes sense when its section is rendered.
    private var anchors: [DetailAnchor] {
        DetailAnchor.allCases.filter { $0 != .category || !sortedBase.isEmpty }
    }

    private func jumpMenu(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(anchors, id: \.self) { anchor in
                Button(anchor.rawValue) {
                    withAnimation { proxy.scrollTo(anchor, anchor: .top) }
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
                PhotosSection(asset: asset)
                    .id(DetailAnchor.photos)
                EventsSection(asset: asset, sheetMode: $eventSheetMode)
                    .id(DetailAnchor.events)
                TransactionsSection(asset: asset, sheetMode: $transactionSheetMode)
                    .id(DetailAnchor.transactions)
                Section("Relationship") {
                    BelongsToRow(asset: asset)
                        .pagingExcludedRow(id: "relationship")
                }
                .id(DetailAnchor.relationship)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    jumpMenu(proxy)
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
                        addEventPresented = true
                    } label: {
                        Label("Event", systemImage: "calendar")
                    }
                    Button {
                        addTransactionPresented = true
                    } label: {
                        Label("Transaction", systemImage: "dollarsign.circle")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Delete Asset", role: .destructive) {
                    deleteConfirmationPresented = true
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
                Text("\(childCount) item\(childCount == 1 ? "" : "s") inside will not be deleted and will lose association.")
            }
        }
    }
}

// MARK: - Belongs-to row

struct BelongsToRow: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    @State private var pickerPresented = false

    private var parent: Asset? {
        guard let id = asset.parentID else { return nil }
        return store.assets[id]
    }

    var body: some View {
        LabeledContent("Belongs to") {
            if let parent {
                HStack(spacing: 12) {
                    Text(parent.name)
                        .foregroundStyle(.primary)
                    Button("Change") { pickerPresented = true }
                }
            } else {
                Button("Select…") { pickerPresented = true }
            }
        }
        .sheet(isPresented: $pickerPresented) {
            AssetParentPickerSheet(asset: asset) { selectedID in
                if let newID = selectedID {
                    try? store.moveAsset(assetID: asset.id, toParentID: newID)
                } else {
                    try? store.removeFromParent(assetID: asset.id)
                }
                pickerPresented = false
            }
        }
    }
}

struct AssetParentPickerSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    let onSelect: (UUID?) -> Void

    private var excludedIDs: Set<UUID> {
        var ids = Set(asset.descendants.map(\.id))
        ids.insert(asset.id)
        return ids
    }

    private var candidates: [Asset] {
        store.allAssets
            .filter { !excludedIDs.contains($0.id) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                    } label: {
                        Label("None (top level)", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                if !candidates.isEmpty {
                    Section("Assets") {
                        ForEach(candidates) { candidate in
                            Button {
                                onSelect(candidate.id)
                            } label: {
                                HStack {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(candidate.name)
                                                .foregroundStyle(.primary)
                                            Text(candidate.category.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: candidate.category.iconName)
                                            .foregroundStyle(.tint)
                                    }
                                    Spacer()
                                    if candidate.id == asset.parentID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Belongs To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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

// MARK: - Property detail rows

private struct PropertyDetailRow: View {
    let assetID: UUID
    let property: AssetProperty
    var onEditLabel: (() -> Void)? = nil

    var body: some View {
        switch property.definition.type {
        case .basic(.text):
            TextDetailField(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.contact):
            ContactDetailRow(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.number):
            NumberDetailField(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.currency):
            CurrencyDetailField(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.date):
            DateDetailRow(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .comboList(let list):
            ComboListDetailRow(assetID: assetID, property: property, list: list, onEditLabel: onEditLabel)
        case .composite(let def):
            CompositeDetailLink(assetID: assetID, property: property, definition: def, onEditLabel: onEditLabel)
        default:
            LabeledContent {
                Text("—").foregroundStyle(.tertiary)
            } label: {
                if let onEditLabel {
                    Button(property.definition.name) { onEditLabel() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                } else {
                    Text(property.definition.name)
                }
            }
        }
    }
}

private struct ContactDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var pickerPresented = false
    @State private var resolvedContact: CNContact?

    private var identifier: String? {
        if case .contact(let s) = property.value { return s }
        return nil
    }

    private var resolvedName: String? {
        guard let id = identifier else { return nil }
        return ContactResolver.shared.displayName(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabeledContent {
                if identifier != nil {
                    HStack(spacing: 12) {
                        if let name = resolvedName {
                            Text(name).foregroundStyle(.secondary)
                        } else {
                            Text("(not found)").foregroundStyle(.tertiary)
                        }
                        Button { pickerPresented = true } label: {
                            Image(systemName: "person.crop.circle")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Button { pickerPresented = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            } label: {
                if let onEditLabel {
                    Button(property.definition.name) { onEditLabel() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                } else {
                    Text(property.definition.name)
                }
            }

            if let contact = resolvedContact {
                ContactActionBar(contact: contact)
            }
        }
        .background(
            ContactPicker(isPresented: $pickerPresented) { id, _ in
                try? store.setPropertyValue(.contact(id), forDefinitionID: property.definition.id, onAssetID: assetID)
            }
        )
        .task(id: identifier) {
            guard let id = identifier else { resolvedContact = nil; return }
            resolvedContact = try? ContactResolver.shared.contact(for: id)
        }
    }
}

private struct ContactActionBar: View {
    let contact: CNContact

    private var firstPhone: String? {
        contact.phoneNumbers.first?.value.stringValue
    }

    private var firstEmail: String? {
        contact.emailAddresses.first.map { $0.value as String }
    }

    private var whatsAppPhone: String? {
        let hasWhatsApp = contact.instantMessageAddresses.contains {
            $0.value.service.lowercased() == "whatsapp"
        }
        guard hasWhatsApp, let phone = firstPhone else { return nil }
        return phone.filter { $0.isNumber || $0 == "+" }
    }

    var body: some View {
        HStack(spacing: 28) {
            if let phone = firstPhone {
                actionButton(systemImage: "phone.fill", color: .accentColor) {
                    open("tel:\(phone.filter { $0.isNumber || $0 == "+" })")
                }
                actionButton(systemImage: "message.fill", color: .accentColor) {
                    open("sms:\(phone.filter { $0.isNumber || $0 == "+" })")
                }
            }
            if let email = firstEmail {
                actionButton(systemImage: "envelope.fill", color: .accentColor) {
                    open("mailto:\(email)")
                }
            }
            if let number = whatsAppPhone {
                actionButton(systemImage: "phone.fill", color: .green) {
                    open("whatsapp://call?phone=\(number)")
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func actionButton(systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct TextDetailField: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty, onEditLabel: (() -> Void)? = nil) {
        self.assetID = assetID
        self.property = property
        self.onEditLabel = onEditLabel
        if case .text(let s) = property.value { _text = State(initialValue: s) }
        else { _text = State(initialValue: "") }
    }

    var body: some View {
        LabeledContent {
            TextField("", text: $text, axis: .vertical)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: property.value) { _, newValue in
                    guard !isFocused else { return }
                    if case .text(let s) = newValue { text = s } else { text = "" }
                }
        } label: {
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }

    private func commit() {
        if text.isEmpty {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        } else {
            try? store.setPropertyValue(.text(text), forDefinitionID: property.definition.id, onAssetID: assetID)
        }
    }
}

private struct NumberDetailField: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty, onEditLabel: (() -> Void)? = nil) {
        self.assetID = assetID
        self.property = property
        self.onEditLabel = onEditLabel
        if case .number(let d) = property.value { _text = State(initialValue: "\(d)") }
        else { _text = State(initialValue: "") }
    }

    var body: some View {
        LabeledContent {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: property.value) { _, newValue in
                    guard !isFocused else { return }
                    if case .number(let d) = newValue { text = "\(d)" } else { text = "" }
                }
        } label: {
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }

    private func commit() {
        if let d = Double(text) {
            try? store.setPropertyValue(.number(d), forDefinitionID: property.definition.id, onAssetID: assetID)
        } else if text.isEmpty {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        }
    }
}

private struct CurrencyDetailField: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty, onEditLabel: (() -> Void)? = nil) {
        self.assetID = assetID
        self.property = property
        self.onEditLabel = onEditLabel
        if case .currency(let d) = property.value { _text = State(initialValue: "\(d)") }
        else { _text = State(initialValue: "") }
    }

    var body: some View {
        LabeledContent {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: property.value) { _, newValue in
                    guard !isFocused else { return }
                    if case .currency(let d) = newValue { text = "\(d)" } else { text = "" }
                }
        } label: {
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }

    private func commit() {
        if let d = Decimal(string: text) {
            try? store.setPropertyValue(.currency(d), forDefinitionID: property.definition.id, onAssetID: assetID)
        } else if text.isEmpty {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        }
    }
}

private struct CompositeDetailLink: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let definition: CompositeTypeDefinition
    let onEditLabel: (() -> Void)?

    private var valueBinding: Binding<StoredValue?> {
        Binding(
            get: { property.value },
            set: { newValue in
                if let newValue {
                    try? store.setPropertyValue(newValue, forDefinitionID: property.definition.id, onAssetID: assetID)
                } else {
                    try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                }
            }
        )
    }

    var body: some View {
        // The trailing summary is the NavigationLink (drill-in to edit values); the
        // label stays a rename Button for custom properties. Keeping them as separate
        // tap targets avoids nesting a Button inside a NavigationLink.
        LabeledContent {
            NavigationLink {
                CompositeEditView(definition: definition, value: valueBinding)
            } label: {
                let summary = property.value?.compositeSummary(for: definition) ?? ""
                Text(summary.isEmpty ? "—" : summary)
                    .foregroundStyle(summary.isEmpty ? .tertiary : .secondary)
            }
        } label: {
            let title = definition.decoratedLabel(property.definition.name)
            if let onEditLabel {
                Button(title) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(title)
            }
        }
    }
}

private struct DateDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?

    private var dateBinding: Binding<Date> {
        Binding(
            get: { if case .date(let d) = property.value { return d }; return Date() },
            set: { date in try? store.setPropertyValue(.date(date), forDefinitionID: property.definition.id, onAssetID: assetID) }
        )
    }

    var body: some View {
        LabeledContent {
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
        } label: {
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }
}

private struct ComboListDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let list: ComboListDefinition
    let onEditLabel: (() -> Void)?

    private var selectionBinding: Binding<String> {
        Binding(
            get: { if case .text(let s) = property.value { return s }; return "" },
            set: { option in
                if option.isEmpty {
                    try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                } else {
                    try? store.setPropertyValue(.text(option), forDefinitionID: property.definition.id, onAssetID: assetID)
                }
            }
        )
    }

    var body: some View {
        LabeledContent {
            Picker("", selection: selectionBinding) {
                Text("—").tag("")
                ForEach(list.allOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
        } label: {
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }
}
