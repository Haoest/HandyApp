import SwiftUI

struct AssetDetailView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    @State private var deleteConfirmationPresented = false
    @State private var addPropertyPresented = false
    @State private var customPropertyToEdit: AssetProperty?

    private var sortedBase: [AssetProperty] {
        asset.baseProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedCustom: [AssetProperty] {
        _ = asset.modifiedDate
        return asset.customProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var childCount: Int { asset.children.count }

    var body: some View {
        Form {
            Section("Name") {
                NameDetailField(asset: asset)
            }
            if !sortedBase.isEmpty {
                Section(asset.category.name) {
                    ForEach(sortedBase) { prop in
                        PropertyDetailRow(assetID: asset.id, property: prop)
                    }
                }
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
            Section("Relationship") {
                BelongsToRow(asset: asset)
            }
        }
        .navigationTitle(asset.name)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Delete Asset", role: .destructive) {
                    deleteConfirmationPresented = true
                }
            }
        }
        .sheet(isPresented: $addPropertyPresented) {
            PropertyEditView { definition, value in
                try? store.addCustomProperty(definition: definition, value: value, toAssetID: asset.id)
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

private struct BelongsToRow: View {
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

private struct AssetParentPickerSheet: View {
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
        case .basic(.text), .basic(.contact):
            TextDetailField(assetID: assetID, property: property, onEditLabel: onEditLabel)
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
                    switch newValue {
                    case .text(let s): text = s
                    case .contact(let s): text = s
                    default: text = ""
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
            let title = "\(property.definition.name) (\(definition.fieldInitials))"
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
