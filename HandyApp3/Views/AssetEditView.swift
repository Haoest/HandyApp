import SwiftUI

struct AssetEditView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let asset: Asset
    var onDismissSheet: (() -> Void)? = nil

    @State private var name: String
    @State private var drafts: [UUID: StoredValue?]

    init(asset: Asset, onDismissSheet: (() -> Void)? = nil) {
        self.asset = asset
        self.onDismissSheet = onDismissSheet
        _name = State(initialValue: asset.name)
        var d: [UUID: StoredValue?] = [:]
        for prop in asset.baseProperties { d[prop.definition.id] = prop.value }
        _drafts = State(initialValue: d)
    }

    private var sortedProperties: [AssetProperty] {
        asset.baseProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Asset name", text: $name)
            }
            if !sortedProperties.isEmpty {
                Section("Properties") {
                    ForEach(sortedProperties) { prop in
                        PropertyEditRow(
                            property: prop,
                            value: draftBinding(for: prop.definition.id)
                        )
                    }
                }
            }
        }
        .navigationTitle("New \(asset.category.name)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    try? store.deleteAsset(id: asset.id)
                    if let onDismissSheet { onDismissSheet() } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    commit()
                    if let onDismissSheet { onDismissSheet() } else { dismiss() }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func draftBinding(for defID: UUID) -> Binding<StoredValue?> {
        Binding(
            get: { self.drafts[defID] ?? nil },
            set: { self.drafts[defID] = $0 }
        )
    }

    private func commit() {
        try? store.updateAsset(id: asset.id, name: name.trimmingCharacters(in: .whitespaces))
        for (defID, value) in drafts {
            if let v = value {
                try? store.setPropertyValue(v, forDefinitionID: defID, onAssetID: asset.id)
            }
        }
    }
}

// MARK: - New asset sheet

struct NewAssetSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var createdAsset: Asset?

    var body: some View {
        NavigationStack {
            CategoryPickerContent { asset in createdAsset = asset }
                .navigationTitle("New Asset")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(isPresented: Binding(
                    get: { createdAsset != nil },
                    set: { presented in
                        if !presented {
                            if let asset = createdAsset { try? store.deleteAsset(id: asset.id) }
                            createdAsset = nil
                        }
                    }
                )) {
                    if let asset = createdAsset {
                        AssetEditView(asset: asset, onDismissSheet: { dismiss() })
                    }
                }
        }
    }
}

private struct CategoryPickerContent: View {
    @Environment(AssetStore.self) private var store
    let onCreate: (Asset) -> Void

    private var sortedCategories: [AssetCategory] {
        store.allCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if store.allCategories.isEmpty {
            ContentUnavailableView(
                "No Categories",
                systemImage: "folder",
                description: Text("Create a category first in the Categories tab.")
            )
        } else {
            List {
                Section("Select Category") {
                    ForEach(sortedCategories) { category in
                        Button(category.name) {
                            let count = (try? store.assets(ofCategoryID: category.id))?.count ?? 0
                            if let asset = try? store.createAsset(
                                name: "\(category.name) \(count + 1)",
                                categoryID: category.id
                            ) {
                                onCreate(asset)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Property edit rows

private struct PropertyEditRow: View {
    let property: AssetProperty
    @Binding var value: StoredValue?

    var body: some View {
        switch property.definition.type {
        case .basic(.text), .basic(.contact):
            TextEditRow(label: property.definition.name, value: $value)
        case .basic(.number):
            NumberEditRow(label: property.definition.name, value: $value)
        case .basic(.currency):
            CurrencyEditRow(label: property.definition.name, value: $value)
        case .basic(.date):
            DateEditRow(label: property.definition.name, value: $value)
        case .comboList(let list):
            ComboListEditRow(label: property.definition.name, list: list, value: $value)
        default:
            LabeledContent(property.definition.name) {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}

private struct TextEditRow: View {
    let label: String
    @Binding var value: StoredValue?

    private var text: Binding<String> {
        Binding(
            get: { if case .text(let s) = value { return s }; return "" },
            set: { value = $0.isEmpty ? nil : .text($0) }
        )
    }

    var body: some View {
        LabeledContent(label) {
            TextField("", text: text, axis: .vertical)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct NumberEditRow: View {
    let label: String
    @Binding var value: StoredValue?
    @State private var text: String

    init(label: String, value: Binding<StoredValue?>) {
        self.label = label
        self._value = value
        if case .number(let d) = value.wrappedValue {
            _text = State(initialValue: "\(d)")
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        LabeledContent(label) {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, new in
                    if let d = Double(new) { value = .number(d) }
                    else if new.isEmpty { value = nil }
                }
        }
    }
}

private struct CurrencyEditRow: View {
    let label: String
    @Binding var value: StoredValue?
    @State private var text: String

    init(label: String, value: Binding<StoredValue?>) {
        self.label = label
        self._value = value
        if case .currency(let d) = value.wrappedValue {
            _text = State(initialValue: "\(d)")
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        LabeledContent(label) {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, new in
                    if let d = Decimal(string: new) { value = .currency(d) }
                    else if new.isEmpty { value = nil }
                }
        }
    }
}

private struct DateEditRow: View {
    let label: String
    @Binding var value: StoredValue?

    private var date: Binding<Date> {
        Binding(
            get: { if case .date(let d) = value { return d }; return Date() },
            set: { value = .date($0) }
        )
    }

    var body: some View {
        DatePicker(label, selection: date, displayedComponents: .date)
    }
}

private struct ComboListEditRow: View {
    let label: String
    let list: ComboListDefinition
    @Binding var value: StoredValue?

    private var selection: Binding<String> {
        Binding(
            get: { if case .text(let s) = value { return s }; return "" },
            set: { value = $0.isEmpty ? nil : .text($0) }
        )
    }

    var body: some View {
        Picker(label, selection: selection) {
            Text("—").tag("")
            ForEach(list.allOptions, id: \.self) { option in
                Text(option).tag(option)
            }
        }
    }
}
