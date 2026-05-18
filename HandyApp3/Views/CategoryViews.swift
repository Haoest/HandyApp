import SwiftUI

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
                            onViewAssets: { navigationPath = .init(); navigationPath.append(CategoryDest.assets(category.id)) },
                            onViewDefs: { navigationPath = .init(); navigationPath.append(CategoryDest.propertyDefs(category.id)) }
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
            .sheet(item: $assetToEdit) { asset in NavigationStack { AssetEditView(asset: asset) } }
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
                    Label(category.name, systemImage: category.iconName)
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

// MARK: - Category detail (property definitions + default values)

struct CategoryPropertyDefsView: View {
    @Environment(AssetStore.self) private var store
    let category: AssetCategory

    var body: some View {
        Form {
            Section {
                ForEach(category.propertyTemplates) { prop in
                    TemplatePropertyRow(categoryID: category.id, property: prop)
                }
            } header: {
                Text("Default Values")
            } footer: {
                Text("These values are copied into new assets created from this category.")
                    .font(.caption)
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TemplatePropertyRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty

    var body: some View {
        switch property.definition.type {
        case .basic(.text), .basic(.contact):
            TemplateTextRow(categoryID: categoryID, property: property)
        case .basic(.number):
            TemplateNumberRow(categoryID: categoryID, property: property)
        case .basic(.currency):
            TemplateCurrencyRow(categoryID: categoryID, property: property)
        case .basic(.date):
            TemplateDateRow(categoryID: categoryID, property: property)
        case .comboList(let list):
            TemplateComboRow(categoryID: categoryID, property: property, list: list)
        default:
            LabeledContent(property.definition.name) {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}

private struct TemplateTextRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(categoryID: UUID, property: AssetProperty) {
        self.categoryID = categoryID
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
            try? store.removeTemplatePropertyValue(forPropertyID: property.id, inCategoryID: categoryID)
        } else {
            try? store.setTemplatePropertyValue(.text(text), forPropertyID: property.id, inCategoryID: categoryID)
        }
    }
}

private struct TemplateNumberRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(categoryID: UUID, property: AssetProperty) {
        self.categoryID = categoryID
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
            try? store.setTemplatePropertyValue(.number(d), forPropertyID: property.id, inCategoryID: categoryID)
        } else if text.isEmpty {
            try? store.removeTemplatePropertyValue(forPropertyID: property.id, inCategoryID: categoryID)
        }
    }
}

private struct TemplateCurrencyRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(categoryID: UUID, property: AssetProperty) {
        self.categoryID = categoryID
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
            try? store.setTemplatePropertyValue(.currency(d), forPropertyID: property.id, inCategoryID: categoryID)
        } else if text.isEmpty {
            try? store.removeTemplatePropertyValue(forPropertyID: property.id, inCategoryID: categoryID)
        }
    }
}

private struct TemplateDateRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty

    private var dateBinding: Binding<Date> {
        Binding(
            get: { if case .date(let d) = property.value { return d }; return Date() },
            set: { try? store.setTemplatePropertyValue(.date($0), forPropertyID: property.id, inCategoryID: categoryID) }
        )
    }

    var body: some View {
        DatePicker(property.definition.name, selection: dateBinding, displayedComponents: .date)
    }
}

private struct TemplateComboRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    let list: ComboListDefinition

    private var selectionBinding: Binding<String> {
        Binding(
            get: { if case .text(let s) = property.value { return s }; return "" },
            set: { option in
                if option.isEmpty {
                    try? store.removeTemplatePropertyValue(forPropertyID: property.id, inCategoryID: categoryID)
                } else {
                    try? store.setTemplatePropertyValue(.text(option), forPropertyID: property.id, inCategoryID: categoryID)
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
