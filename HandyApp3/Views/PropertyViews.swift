import SwiftUI
import UIKit

// MARK: - Property edit view

struct PropertyEditView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: AssetProperty?
    let onSave: (PropertyDefinition, StoredValue?) -> Void

    init(existing: AssetProperty? = nil, onSave: @escaping (PropertyDefinition, StoredValue?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.definition.name ?? "")
    }

    @State private var name: String
    @State private var selectedTypeIndex: Int = 0
    @State private var valueText: String = ""
    @State private var valueDate: Date = Date()
    @State private var valueDateEnabled: Bool = false
    @State private var valueCombo: String = ""
    @FocusState private var nameFieldFocused: Bool

    private var availableTypes: [PropertyType] {
        let basics: [PropertyType] = [
            .basic(.text), .basic(.number), .basic(.currency), .basic(.date), .basic(.contact),
        ]
        let composites = store.allCompositeTypes
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            .map { PropertyType.composite($0) }
        let combos = store.allComboListDefinitions
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            .map { PropertyType.comboList($0) }
        return basics + composites + combos
    }

    private var currentType: PropertyType { availableTypes[selectedTypeIndex] }

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
            return valueText.isEmpty ? nil : .contact(valueText)
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
        case .basic(.data), .composite: return false
        default: return true
        }
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
                        get: { selectedTypeIndex },
                        set: { selectedTypeIndex = $0; clearValue() }
                    )) {
                        ForEach(availableTypes.indices, id: \.self) { i in
                            Text(availableTypes[i].displayName).tag(i)
                        }
                    }
                    .pickerStyle(.menu)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let def = PropertyDefinition(
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: availableTypes[selectedTypeIndex]
                        )
                        onSave(def, enteredValue)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var valueField: some View {
        switch currentType {
        case .basic(.text):
            TextField("Optional", text: $valueText)
        case .basic(.contact):
            TextField("Optional", text: $valueText)
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
            Picker("", selection: $valueCombo) {
                Text("None").tag("")
                ForEach(list.allOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        default:
            EmptyView()
        }
    }

    private func prepopulate() {
        if let existing {
            if let idx = availableTypes.firstIndex(where: { $0 == existing.definition.type }) {
                selectedTypeIndex = idx
            }
            if let value = existing.value {
                let type = existing.definition.type
                switch value {
                case .text(let s):
                    if case .comboList = type { valueCombo = s } else { valueText = s }
                case .number(let d): valueText = "\(d)"
                case .currency(let d): valueText = "\(d)"
                case .date(let d): valueDate = d; valueDateEnabled = true
                case .contact(let s): valueText = s
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
    }
}
