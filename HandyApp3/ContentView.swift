import SwiftUI

// MARK: - Root

struct ContentView: View {
    var body: some View {
        TabView {
            HomeTab()
                .tabItem { Image(systemName: "house") }
            AssetTab()
                .tabItem { Image(systemName: "shippingbox") }
            CategoryTab()
                .tabItem { Image(systemName: "folder") }
            ActivityTab()
                .tabItem { Image(systemName: "waveform") }
            PreferenceTab()
                .tabItem { Image(systemName: "gearshape") }
        }
    }
}

// MARK: - Home tab

struct HomeTab: View {
    var body: some View {
        NavigationStack {
            Text("Home")
                .navigationTitle("Home")
        }
    }
}

// MARK: - Asset tab

struct AssetTab: View {
    @Environment(AssetStore.self) private var store
    @State private var newAssetPresented = false

    private var sortedAssets: [Asset] {
        store.allAssets.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.allAssets.isEmpty {
                    ContentUnavailableView(
                        "No Assets",
                        systemImage: "shippingbox",
                        description: Text("Tap + to add your first asset.")
                    )
                } else {
                    List(sortedAssets) { asset in
                        NavigationLink(destination: AssetDetailView(asset: asset)) {
                            AssetRow(asset: asset)
                        }
                    }
                }
            }
            .navigationTitle("Assets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newAssetPresented = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $newAssetPresented) {
                NewAssetView()
            }
        }
    }
}

// MARK: - Category tab

private enum CategoryDest: Hashable {
    case assets(UUID)
    case propertyDefs(UUID)
}

struct CategoryTab: View {
    @Environment(AssetStore.self) private var store
    @State private var navigationPath = NavigationPath()
    @State private var expandedCategoryID: UUID?
    @State private var newCategoryPresented = false
    @State private var assetToEdit: Asset?

    private var sortedCategories: [AssetCategory] {
        store.allCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if store.allCategories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "folder",
                        description: Text("Tap + to create your first category.")
                    )
                } else {
                    List(sortedCategories) { category in
                        CategoryRow(
                            category: category,
                            isExpanded: expandedCategoryID == category.id,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedCategoryID = expandedCategoryID == category.id ? nil : category.id
                                }
                            },
                            onNewAsset: {
                                let count = (try? store.assets(ofCategoryID: category.id))?.count ?? 0
                                let defaultName = "\(category.name) \(count + 1)"
                                if let asset = try? store.createAsset(name: defaultName, categoryID: category.id) {
                                    assetToEdit = asset
                                }
                            },
                            onViewAssets: { navigationPath.append(CategoryDest.assets(category.id)) },
                            onViewDefs: { navigationPath.append(CategoryDest.propertyDefs(category.id)) }
                        )
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newCategoryPresented = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: CategoryDest.self) { dest in
                switch dest {
                case .assets(let id):
                    if let cat = store.categories[id] { CategoryAssetsView(category: cat) }
                case .propertyDefs(let id):
                    if let cat = store.categories[id] { CategoryPropertyDefsView(category: cat) }
                }
            }
            .sheet(isPresented: $newCategoryPresented) { NewCategoryView() }
            .sheet(item: $assetToEdit) { asset in AssetEditView(asset: asset) }
        }
    }
}

// MARK: - Category row

private struct CategoryRow: View {
    let category: AssetCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    let onNewAsset: () -> Void
    let onViewAssets: () -> Void
    let onViewDefs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onToggle) {
                    Text(category.name)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onNewAsset) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                HStack(spacing: 32) {
                    Button(action: onViewAssets) {
                        VStack(spacing: 4) {
                            Image(systemName: "shippingbox")
                                .imageScale(.large)
                            Text("Assets")
                                .font(.caption2)
                        }
                    }
                    Button(action: onViewDefs) {
                        VStack(spacing: 4) {
                            Image(systemName: "list.bullet.clipboard")
                                .imageScale(.large)
                            Text("Definitions")
                                .font(.caption2)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category assets list

struct CategoryAssetsView: View {
    let category: AssetCategory

    var body: some View {
        Text("Assets in \(category.name)")
            .navigationTitle("Assets")
    }
}

// MARK: - Category property definitions

struct CategoryPropertyDefsView: View {
    let category: AssetCategory

    var body: some View {
        List(category.propertyTemplates) { prop in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(prop.definition.name)
                    Spacer()
                    if prop.definition.isRequired {
                        Text("required")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.12))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                    }
                }
                Text(prop.definition.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("Property Definitions")
    }
}

// MARK: - Activity tab

struct ActivityTab: View {
    var body: some View {
        NavigationStack {
            Text("Activity")
                .navigationTitle("Activity")
        }
    }
}

// MARK: - Preference tab

struct PreferenceTab: View {
    var body: some View {
        NavigationStack {
            Text("Preferences")
                .navigationTitle("Preferences")
        }
    }
}

// MARK: - Asset row

private struct AssetRow: View {
    let asset: Asset

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.name)
                .font(.body)
            HStack {
                Text(asset.category.name)
                Spacer()
                Text(asset.modifiedDate, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Asset edit view

struct AssetEditView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let asset: Asset

    @State private var name: String
    @State private var drafts: [UUID: StoredValue?]

    init(asset: Asset) {
        self.asset = asset
        _name = State(initialValue: asset.name)
        var d: [UUID: StoredValue?] = [:]
        for prop in asset.baseProperties { d[prop.definition.id] = prop.value }
        _drafts = State(initialValue: d)
    }

    private var sortedProperties: [AssetProperty] {
        asset.baseProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        try? store.deleteAsset(id: asset.id)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commit()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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

// MARK: - Property edit row

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

struct NewAssetView: View {
    var body: some View {
        NavigationStack {
            Text("New Asset")
                .navigationTitle("New Asset")
        }
    }
}

struct NewCategoryView: View {
    var body: some View {
        NavigationStack {
            Text("New Category")
                .navigationTitle("New Category")
        }
    }
}

// MARK: - Asset detail view

struct AssetDetailView: View {
    let asset: Asset

    private var sortedBase: [AssetProperty] {
        asset.baseProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedCustom: [AssetProperty] {
        asset.customProperties.sorted { $0.sortOrder < $1.sortOrder }
    }

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
            if !sortedCustom.isEmpty {
                Section("Custom") {
                    ForEach(sortedCustom) { prop in
                        PropertyDetailRow(assetID: asset.id, property: prop)
                    }
                }
            }
        }
        .navigationTitle(asset.name)
    }
}

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

private struct PropertyDetailRow: View {
    let assetID: UUID
    let property: AssetProperty

    var body: some View {
        switch property.definition.type {
        case .basic(.text), .basic(.contact):
            TextDetailField(assetID: assetID, property: property)
        case .basic(.number):
            NumberDetailField(assetID: assetID, property: property)
        case .basic(.currency):
            CurrencyDetailField(assetID: assetID, property: property)
        case .basic(.date):
            DateDetailRow(assetID: assetID, property: property)
        case .comboList(let list):
            ComboListDetailRow(assetID: assetID, property: property, list: list)
        default:
            LabeledContent(property.definition.name) {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}

private struct TextDetailField: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty) {
        self.assetID = assetID
        self.property = property
        if case .text(let s) = property.value { _text = State(initialValue: s) }
        else { _text = State(initialValue: "") }
    }

    var body: some View {
        LabeledContent(property.definition.name) {
            TextField("", text: $text, axis: .vertical)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
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
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty) {
        self.assetID = assetID
        self.property = property
        if case .number(let d) = property.value { _text = State(initialValue: "\(d)") }
        else { _text = State(initialValue: "") }
    }

    var body: some View {
        LabeledContent(property.definition.name) {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
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
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty) {
        self.assetID = assetID
        self.property = property
        if case .currency(let d) = property.value { _text = State(initialValue: "\(d)") }
        else { _text = State(initialValue: "") }
    }

    var body: some View {
        LabeledContent(property.definition.name) {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
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

private struct DateDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty

    private var dateBinding: Binding<Date> {
        Binding(
            get: { if case .date(let d) = property.value { return d }; return Date() },
            set: { date in try? store.setPropertyValue(.date(date), forDefinitionID: property.definition.id, onAssetID: assetID) }
        )
    }

    var body: some View {
        DatePicker(property.definition.name, selection: dateBinding, displayedComponents: .date)
    }
}

private struct ComboListDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let list: ComboListDefinition

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
        Picker(property.definition.name, selection: selectionBinding) {
            Text("—").tag("")
            ForEach(list.allOptions, id: \.self) { option in
                Text(option).tag(option)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let store = AssetStore()
    store.seedBuiltInComboLists()
    store.seedBuiltInCategories()
    let catID = store.allCategories.first!.id
    try? store.createAsset(name: "2022 Toyota Camry", categoryID: catID)
    try? store.createAsset(name: "Bosch Refrigerator", categoryID: catID)
    return ContentView()
        .environment(store)
}
