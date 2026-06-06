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
                            onViewDefs: { navigationPath = .init(); navigationPath.append(CategoryDest.propertyDefs(category.id)) },
                            onChangeIcon: { newIcon in
                                try? store.updateCategoryIcon(id: category.id, iconName: newIcon)
                            }
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
            .sheet(isPresented: $newCategoryPresented) { CategoryNewView() }
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
    let onChangeIcon: (String) -> Void

    @State private var iconPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { iconPickerPresented = true } label: {
                    Image(systemName: category.iconName)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

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
        .sheet(isPresented: $iconPickerPresented) {
            IconPickerView(current: category.iconName) { newIcon in
                onChangeIcon(newIcon)
                iconPickerPresented = false
            }
        }
    }
}

// MARK: - Icon picker

struct IconPickerView: View {
    let current: String
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private static let icons: [String] = [
        // Home & building
        "house", "house.fill", "building.2", "building.columns", "door.left.hand.closed",
        "window.horizontal", "archivebox", "tray", "tray.2",
        // Electronics
        "tv", "desktopcomputer", "laptopcomputer", "ipad", "iphone",
        "headphones", "speaker.wave.2", "hifispeaker", "printer", "keyboard",
        "mouse", "gamecontroller", "camera", "video", "photo",
        // Appliances
        "refrigerator", "washer", "dryer", "dishwasher", "oven",
        "microwave", "fan", "air.conditioner.vertical", "lightbulb", "lamp.desk",
        // Furniture
        "sofa", "bed.double", "table.furniture", "chair",
        // Vehicles
        "car", "car.fill", "truck.box", "bus", "bicycle",
        "scooter", "airplane", "ferry", "fuelpump",
        // Tools & hardware
        "wrench", "hammer", "screwdriver", "paintbrush", "shovel",
        "wrench.and.screwdriver", "gear", "gearshape", "gearshape.2",
        "bolt", "bolt.fill", "flashlight.on.fill",
        // Garden & outdoors
        "leaf", "tree", "drop.fill", "sun.max", "cloud",
        "snowflake", "flame", "wind", "umbrella",
        // Sports & hobbies
        "sportscourt", "football", "basketball", "baseball",
        "figure.run", "dumbbell", "guitar", "piano.keys",
        // Bags & clothing
        "tshirt", "briefcase", "bag", "handbag", "backpack", "suitcase",
        // Medical
        "cross.case", "pills", "stethoscope", "bandage", "heart",
        // Finance
        "creditcard", "banknote", "wallet.bifold", "dollarsign.circle",
        // Office
        "doc", "folder", "paperclip", "ruler", "pencil", "scissors",
        "book", "books.vertical", "magazine", "calendar", "clock",
        // Nature & pets
        "pawprint", "fish", "bird", "tortoise", "ant",
        // Food
        "fork.knife", "cup.and.saucer", "wineglass", "birthday.cake",
        // General
        "star", "bookmark", "tag", "flag", "location", "globe", "map",
        "bell", "music.note", "film", "alarm", "cart", "gift",
        "lock", "key", "person", "person.2", "barcode", "qrcode",
        "square.grid.2x2", "circle.grid.2x2", "rectangle.3.group",
    ]

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? Self.icons : Self.icons.filter { $0.contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach(filtered, id: \.self) { name in
                        Button { onSelect(name) } label: {
                            iconCell(name: name)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search symbols")
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func iconCell(name: String) -> some View {
        let selected = name == current
        let bg: Color = selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemGroupedBackground)
        let border: Color = selected ? Color.accentColor : .clear
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(bg)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 2))
            Image(systemName: name)
                .font(.title2)
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        }
        .frame(width: 56, height: 56)
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
    @State private var iconPickerPresented = false
    @State private var addPropertyPresented = false
    @State private var propertyToEdit: AssetProperty?

    var body: some View {
        Form {
            Section {
                Button { iconPickerPresented = true } label: {
                    HStack {
                        Spacer()
                        Image(systemName: category.iconName)
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Text("Change Icon")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { iconPickerPresented = true }
            }

            Section {
                ForEach(category.propertyTemplates) { prop in
                    TemplatePropertyRow(categoryID: category.id, property: prop, onEditLabel: { propertyToEdit = prop })
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                try? store.removeTemplateProperty(id: prop.id, fromCategoryID: category.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addPropertyPresented = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $iconPickerPresented) {
            IconPickerView(current: category.iconName) { newIcon in
                try? store.updateCategoryIcon(id: category.id, iconName: newIcon)
                iconPickerPresented = false
            }
        }
        .sheet(isPresented: $addPropertyPresented) {
            PropertyEditView { definition, value in
                let prop = AssetProperty(definition: definition, value: value)
                try? store.addTemplateProperty(prop, toCategoryID: category.id)
            }
        }
        .sheet(item: $propertyToEdit) { prop in
            PropertyEditView(existing: prop) { definition, value in
                try? store.updateTemplateProperty(id: prop.id, inCategoryID: category.id, name: definition.name, type: definition.type)
                if let value {
                    try? store.setTemplatePropertyValue(value, forPropertyID: prop.id, inCategoryID: category.id)
                } else {
                    try? store.removeTemplatePropertyValue(forPropertyID: prop.id, inCategoryID: category.id)
                }
            }
        }
    }
}

private struct TemplatePropertyRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    let onEditLabel: () -> Void

    var body: some View {
        switch property.definition.type {
        case .basic(.text), .basic(.contact):
            TemplateTextRow(categoryID: categoryID, property: property, onEditLabel: onEditLabel)
        case .basic(.number):
            TemplateNumberRow(categoryID: categoryID, property: property, onEditLabel: onEditLabel)
        case .basic(.currency):
            TemplateCurrencyRow(categoryID: categoryID, property: property, onEditLabel: onEditLabel)
        case .basic(.date):
            TemplateDateRow(categoryID: categoryID, property: property, onEditLabel: onEditLabel)
        case .comboList(let list):
            TemplateComboRow(categoryID: categoryID, property: property, list: list, onEditLabel: onEditLabel)
        case .composite(let def):
            TemplateCompositeRow(categoryID: categoryID, property: property, definition: def, onEditLabel: onEditLabel)
        default:
            LabeledContent {
                Text("—").foregroundStyle(.tertiary)
            } label: {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct TemplateTextRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    let onEditLabel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(categoryID: UUID, property: AssetProperty, onEditLabel: @escaping () -> Void) {
        self.categoryID = categoryID
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
            Button(property.definition.name) { onEditLabel() }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
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
    let onEditLabel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(categoryID: UUID, property: AssetProperty, onEditLabel: @escaping () -> Void) {
        self.categoryID = categoryID
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
            Button(property.definition.name) { onEditLabel() }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
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
    let onEditLabel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(categoryID: UUID, property: AssetProperty, onEditLabel: @escaping () -> Void) {
        self.categoryID = categoryID
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
            Button(property.definition.name) { onEditLabel() }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
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
    let onEditLabel: () -> Void

    private var dateBinding: Binding<Date> {
        Binding(
            get: { if case .date(let d) = property.value { return d }; return Date() },
            set: { try? store.setTemplatePropertyValue(.date($0), forPropertyID: property.id, inCategoryID: categoryID) }
        )
    }

    var body: some View {
        LabeledContent {
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
        } label: {
            Button(property.definition.name) { onEditLabel() }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
        }
    }
}

private struct TemplateCompositeRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    let definition: CompositeTypeDefinition
    let onEditLabel: () -> Void

    private var valueBinding: Binding<StoredValue?> {
        Binding(
            get: { property.value },
            set: { newValue in
                if let newValue {
                    try? store.setTemplatePropertyValue(newValue, forPropertyID: property.id, inCategoryID: categoryID)
                } else {
                    try? store.removeTemplatePropertyValue(forPropertyID: property.id, inCategoryID: categoryID)
                }
            }
        )
    }

    var body: some View {
        LabeledContent {
            NavigationLink {
                CompositeEditView(definition: definition, value: valueBinding)
            } label: {
                let summary = property.value?.compositeSummary(for: definition) ?? ""
                Text(summary.isEmpty ? "—" : summary)
                    .foregroundStyle(summary.isEmpty ? .tertiary : .secondary)
            }
        } label: {
            Button(definition.decoratedLabel(property.definition.name)) { onEditLabel() }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
        }
    }
}

private struct TemplateComboRow: View {
    @Environment(AssetStore.self) private var store
    let categoryID: UUID
    let property: AssetProperty
    let list: ComboListDefinition
    let onEditLabel: () -> Void

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
        LabeledContent {
            Picker("", selection: selectionBinding) {
                Text("—").tag("")
                ForEach(list.allOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
        } label: {
            Button(property.definition.name) { onEditLabel() }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
        }
    }
}
