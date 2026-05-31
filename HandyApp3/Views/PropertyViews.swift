import SwiftUI
import UIKit

// MARK: - Property edit view

struct PropertyEditView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onSave: (PropertyDefinition) -> Void

    @State private var name: String = ""
    @State private var selectedTypeIndex: Int = 0
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
                    Picker("Type", selection: $selectedTypeIndex) {
                        ForEach(availableTypes.indices, id: \.self) { i in
                            Text(availableTypes[i].displayName).tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("New Property")
            .navigationBarTitleDisplayMode(.inline)
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
                        onSave(def)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
