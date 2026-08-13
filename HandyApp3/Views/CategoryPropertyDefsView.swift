import SwiftUI

// MARK: - Category detail (property definitions + default values)

struct CategoryPropertyDefsView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let category: AssetCategory
    @State private var iconPickerPresented = false
    @State private var addPropertyPresented = false
    @State private var propertyToEdit: AssetProperty?
    @State private var deleteConfirmationPresented = false

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
                CategoryNameField(category: category)
            }

            Section {
                ForEach(category.liveTemplates) { prop in
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

            Section {
                Button(role: .destructive) {
                    deleteConfirmationPresented = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Category")
                        Spacer()
                    }
                }
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
        .confirmationDialog(
            "Delete \"\(category.name)\"?",
            isPresented: $deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Category", role: .destructive) {
                try? store.softDeleteCategory(id: category.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The category will be removed. Existing assets will not be affected.")
        }
    }
}

// MARK: - Name field

private struct CategoryNameField: View {
    @Environment(AssetStore.self) private var store
    let category: AssetCategory
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(category: AssetCategory) {
        self.category = category
        _text = State(initialValue: category.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: "Name", onEditLabel: nil)
            TextField("Name", text: $text)
                .focused($isFocused)
                .onSubmit { commit() }
                .commitsPendingEdit(focused: isFocused) { commit() }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { text = category.name; return }
        guard trimmed != category.name else { return }
        try? store.updateCategory(id: category.id, name: trimmed)
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
            VStack(alignment: .leading, spacing: 4) {
                PropertyLabel(name: property.definition.name, onEditLabel: onEditLabel)
                Text("—").foregroundStyle(.tertiary)
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
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: property.definition.name, onEditLabel: onEditLabel)
            TextField("", text: $text, axis: .vertical)
                .focused($isFocused)
                .onSubmit { commit() }
                .commitsPendingEdit(focused: isFocused) { commit() }
                .onChange(of: property.value) { _, newValue in
                    guard !isFocused else { return }
                    switch newValue {
                    case .text(let s): text = s
                    case .contact(let s): text = s
                    default: text = ""
                    }
                }
        }
    }

    private func commit() {
        let newValue: StoredValue? = text.isEmpty ? nil : .text(text)
        guard newValue != property.value else { return }
        if let newValue {
            try? store.setTemplatePropertyValue(newValue, forPropertyID: property.id, inCategoryID: categoryID)
        } else {
            try? store.removeTemplatePropertyValue(forPropertyID: property.id, inCategoryID: categoryID)
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
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: property.definition.name, onEditLabel: onEditLabel)
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .commitsPendingEdit(focused: isFocused) { commit() }
                .onChange(of: property.value) { _, newValue in
                    guard !isFocused else { return }
                    if case .number(let d) = newValue { text = "\(d)" } else { text = "" }
                }
        }
    }

    private func commit() {
        let newValue: StoredValue?
        if let d = Double(text) { newValue = .number(d) }
        else if text.isEmpty { newValue = nil }
        else { return }   // unparseable draft ("-", "12abc") — leave the stored value alone
        guard newValue != property.value else { return }
        if let newValue {
            try? store.setTemplatePropertyValue(newValue, forPropertyID: property.id, inCategoryID: categoryID)
        } else {
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
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: property.definition.name, onEditLabel: onEditLabel)
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .commitsPendingEdit(focused: isFocused) { commit() }
                .onChange(of: property.value) { _, newValue in
                    guard !isFocused else { return }
                    if case .currency(let d) = newValue { text = "\(d)" } else { text = "" }
                }
        }
    }

    private func commit() {
        let newValue: StoredValue?
        if let d = Decimal(string: text) { newValue = .currency(d) }
        else if text.isEmpty { newValue = nil }
        else { return }   // unparseable draft ("-", "12abc") — leave the stored value alone
        guard newValue != property.value else { return }
        if let newValue {
            try? store.setTemplatePropertyValue(newValue, forPropertyID: property.id, inCategoryID: categoryID)
        } else {
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
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: property.definition.name, onEditLabel: onEditLabel)
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
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
        let title = definition.decoratedLabel(property.definition.name)
        let summary = property.value?.compositeSummary(for: definition) ?? ""
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: title, onEditLabel: onEditLabel)
            NavigationLink {
                CompositeEditView(definition: definition, value: valueBinding)
            } label: {
                Text(summary.isEmpty ? "—" : summary)
                    .foregroundStyle(summary.isEmpty ? .tertiary : .secondary)
            }
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
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: property.definition.name, onEditLabel: onEditLabel)
            Picker("", selection: selectionBinding) {
                Text("—").tag("")
                ForEach(list.allOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
        }
    }
}
