import SwiftUI
import UIKit

// MARK: - Property edit view

struct PropertyEditView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: AssetProperty?
    let onSave: (PropertyDefinition, StoredValue?) -> Void

    /// One entry per selectable row in the Type picker. Combo lists collapse to a single
    /// "Combo list" row rather than one row per list — `selectedComboListID` (below) then picks
    /// which list. `.composite`/`.comboList` carry the definition's id, not the value, so the
    /// selection stays stable if `store.allCompositeTypes`/`allComboListDefinitions` change
    /// while this sheet is open — an `Int` index into a rebuilt array would not.
    private enum TypeChoice: Hashable {
        case basic(BasicType)
        case composite(UUID)
        case comboList
    }

    init(existing: AssetProperty? = nil, onSave: @escaping (PropertyDefinition, StoredValue?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.definition.name ?? "")
        _maxLengthText = State(initialValue: existing?.definition.maxLength.map(String.init)
                                ?? String(PropertyDefinition.defaultTextMaxLength))
        if case .comboList(let list) = existing?.definition.type {
            _typeChoice = State(initialValue: .comboList)
            _selectedComboListID = State(initialValue: list.id)
            _originalComboList = State(initialValue: list)
        } else if case .composite(let ct) = existing?.definition.type {
            _typeChoice = State(initialValue: .composite(ct.id))
        } else if case .basic(let b) = existing?.definition.type {
            _typeChoice = State(initialValue: .basic(b))
        }
    }

    @State private var name: String
    @State private var maxLengthText: String
    @State private var typeChoice: TypeChoice = .basic(.text)
    @State private var selectedComboListID: UUID?
    /// Captured from `existing` at init so a property typed on a since-soft-deleted combo list
    /// still has its list available to pick — otherwise the second picker's selection wouldn't
    /// be among its own options and SwiftUI would silently clear it.
    @State private var originalComboList: ComboListDefinition?
    @State private var valueText: String = ""
    @State private var valueDate: Date = Date()
    @State private var valueDateEnabled: Bool = false
    @State private var valueCombo: String = ""
    @State private var valueContactID: String = ""
    @State private var valueContactName: String = ""
    @State private var contactPickerPresented = false
    @FocusState private var nameFieldFocused: Bool

    private var sortedComposites: [CompositeTypeDefinition] {
        store.allCompositeTypes.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var comboListChoices: [ComboListDefinition] {
        var lists = store.allComboListDefinitions
        if let originalComboList, !lists.contains(where: { $0.id == originalComboList.id }) {
            lists.append(originalComboList)
        }
        return lists.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Resolved from the raw store dict (not `allComboListDefinitions`) so a soft-deleted list
    /// still resolves for a property already typed on it.
    private var currentType: PropertyType? {
        switch typeChoice {
        case .basic(let b):
            return .basic(b)
        case .composite(let id):
            return store.compositeTypes[id].map { .composite($0) }
        case .comboList:
            guard let id = selectedComboListID else { return nil }
            if let list = store.comboListDefinitions[id] { return .comboList(list) }
            if let originalComboList, originalComboList.id == id { return .comboList(originalComboList) }
            return nil
        }
    }

    private var currentWord: String {
        name.components(separatedBy: " ").last ?? ""
    }

    private var suggestions: [String] {
        let word = currentWord
        guard !word.isEmpty else { return [] }
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let completions = checker.completions(forPartialWordRange: range, in: word, language: "en") ?? []
        return Array(completions.prefix(10))
    }

    private var enteredValue: StoredValue? {
        switch currentType {
        case .basic(.text):
            return valueText.isEmpty ? nil : .text(valueText)
        case .basic(.contact):
            return valueContactID.isEmpty ? nil : .contact(valueContactID)
        case .basic(.number):
            return Double(valueText).map { .number($0) }
        case .basic(.currency):
            return Decimal(string: valueText).map { .currency($0) }
        case .basic(.date):
            return valueDateEnabled ? .date(valueDate) : nil
        case .comboList:
            return valueCombo.isEmpty ? nil : .text(valueCombo)
        default:
            return nil
        }
    }

    private var hasEditableValue: Bool {
        switch currentType {
        case .basic(.data), .composite, .none: return false
        default: return true
        }
    }

    /// Whether the currently-selected type takes a character bound — `.basic(.text)` or
    /// `.comboList`, mirroring `PropertyDefinition.acceptsMaxLength`.
    private var typeTakesMaxLength: Bool {
        switch currentType {
        case .basic(.text), .comboList: return true
        default: return false
        }
    }

    private var parsedMaxLength: Int? {
        guard let n = Int(maxLengthText.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (1...PropertyDefinition.systemMaxLength).contains(n) ? n : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Property name", text: $name)
                        .focused($nameFieldFocused)
                        .autocorrectionDisabled()
                    if nameFieldFocused && !suggestions.isEmpty {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                var parts = name.components(separatedBy: " ")
                                parts[parts.count - 1] = suggestion
                                name = parts.joined(separator: " ") + " "
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section("Type") {
                    Picker("Type", selection: Binding(
                        get: { typeChoice },
                        set: { typeChoice = $0; selectedComboListID = nil; clearValue() }
                    )) {
                        Text("Text").tag(TypeChoice.basic(.text))
                        Text("Number").tag(TypeChoice.basic(.number))
                        Text("Currency").tag(TypeChoice.basic(.currency))
                        Text("Date").tag(TypeChoice.basic(.date))
                        Text("Contact").tag(TypeChoice.basic(.contact))
                        ForEach(sortedComposites) { ct in
                            Text(ct.name).tag(TypeChoice.composite(ct.id))
                        }
                        Text("Combo list").tag(TypeChoice.comboList)
                    }
                    .pickerStyle(.menu)

                    if typeChoice == .comboList {
                        if comboListChoices.isEmpty {
                            Text("No combo lists yet. Create one in the Categories tab.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("List", selection: Binding(
                                get: { selectedComboListID },
                                set: { selectedComboListID = $0; clearValue() }
                            )) {
                                Text("Choose…").tag(UUID?.none)
                                ForEach(comboListChoices) { list in
                                    Text(list.name).tag(Optional(list.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                if typeTakesMaxLength {
                    Section {
                        TextField("Max Length", text: $maxLengthText)
                            .keyboardType(.numberPad)
                            .onChange(of: maxLengthText) { _, newValue in
                                let digitsOnly = newValue.filter(\.isNumber)
                                if digitsOnly != newValue { maxLengthText = digitsOnly }
                            }
                    } header: {
                        Text("Max Length")
                    } footer: {
                        Text("The most characters this field can hold, up to \(PropertyDefinition.systemMaxLength).")
                            .font(.caption)
                    }
                }
                if hasEditableValue {
                    Section("Value") {
                        valueField
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Property" : "Edit Property")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { prepopulate() }
            .background(
                ContactPicker(isPresented: $contactPickerPresented) { id, name in
                    valueContactID = id
                    valueContactName = name
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let type = currentType else { return }
                        let def = PropertyDefinition(
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: type,
                            maxLength: typeTakesMaxLength ? parsedMaxLength : nil
                        )
                        onSave(def, enteredValue)
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                        || currentType == nil
                        || (typeTakesMaxLength && parsedMaxLength == nil)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var valueField: some View {
        switch currentType {
        case .basic(.text):
            TextField("Optional", text: $valueText)
                .limitLength(parsedMaxLength, text: $valueText)
        case .basic(.contact):
            Button {
                contactPickerPresented = true
            } label: {
                if !valueContactName.isEmpty {
                    Text(valueContactName).foregroundStyle(.primary)
                } else if !valueContactID.isEmpty {
                    Text("(not found)").foregroundStyle(.tertiary)
                } else {
                    Text("Choose contact…").foregroundStyle(.tint)
                }
            }
        case .basic(.number):
            TextField("Optional", text: $valueText)
                .keyboardType(.decimalPad)
        case .basic(.currency):
            TextField("Optional", text: $valueText)
                .keyboardType(.decimalPad)
        case .basic(.date):
            Toggle("Set value", isOn: $valueDateEnabled)
            if valueDateEnabled {
                DatePicker("", selection: $valueDate, displayedComponents: .date)
                    .labelsHidden()
            }
        case .comboList(let list):
            ComboListField(label: nil, list: list, current: valueCombo) { newValue in
                valueCombo = newValue ?? ""
            }
        default:
            EmptyView()
        }
    }

    private func prepopulate() {
        if let existing {
            if let value = existing.value {
                let type = existing.definition.type
                switch value {
                case .text(let s):
                    if case .comboList = type { valueCombo = s } else { valueText = s }
                case .number(let d): valueText = "\(d)"
                case .currency(let d): valueText = "\(d)"
                case .date(let d): valueDate = d; valueDateEnabled = true
                case .contact(let s):
                    valueContactID = s
                    valueContactName = ContactResolver.shared.displayName(for: s) ?? ""
                default: break
                }
            }
        }
    }

    private func clearValue() {
        valueText = ""
        valueDate = Date()
        valueDateEnabled = false
        valueCombo = ""
        valueContactID = ""
        valueContactName = ""
        maxLengthText = String(PropertyDefinition.defaultTextMaxLength)
    }
}
