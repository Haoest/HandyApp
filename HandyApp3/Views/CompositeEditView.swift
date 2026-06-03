import SwiftUI

/// Drill-in editor for a composite value (e.g. 2D Size). Generic over any
/// `CompositeTypeDefinition`: it renders one row per field, reusing the same
/// `PropertyEditRow` dispatch as the top-level asset form.
///
/// Edits are held in a local working copy and pushed back to `value` as a single
/// `.composite(...)` on disappear, so a half-filled composite never reaches the
/// bound setter (which, for the detail view, runs store validation requiring all
/// required fields).
struct CompositeEditView: View {
    let definition: CompositeTypeDefinition
    @Binding var value: StoredValue?

    @State private var working: [String: StoredValue]

    init(definition: CompositeTypeDefinition, value: Binding<StoredValue?>) {
        self.definition = definition
        self._value = value
        if case .composite(let dict) = value.wrappedValue {
            _working = State(initialValue: dict)
        } else {
            _working = State(initialValue: [:])
        }
    }

    var body: some View {
        Form {
            Section(definition.name) {
                ForEach(definition.fields) { field in
                    PropertyEditRow(definition: field, value: fieldBinding(field.name))
                }
            }
        }
        .navigationTitle(definition.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            value = working.isEmpty ? nil : .composite(working)
        }
    }

    private func fieldBinding(_ name: String) -> Binding<StoredValue?> {
        Binding(
            get: { working[name] },
            set: { sub in
                if let sub { working[name] = sub } else { working.removeValue(forKey: name) }
            }
        )
    }
}
