import SwiftUI

// MARK: - Property edit rows

struct PropertyEditRow: View {
    let definition: PropertyDefinition
    @Binding var value: StoredValue?

    var body: some View {
        switch definition.type {
        case .basic(.text):
            TextEditRow(label: definition.name, value: $value)
        case .basic(.contact):
            ContactEditRow(label: definition.name, value: $value)
        case .basic(.number):
            NumberEditRow(label: definition.name, value: $value)
        case .basic(.currency):
            CurrencyEditRow(label: definition.name, value: $value)
        case .basic(.date):
            DateEditRow(label: definition.name, value: $value)
        case .comboList(let list):
            ComboListEditRow(label: definition.name, list: list, value: $value)
        case .composite(let def):
            CompositeFieldLink(label: definition.name, definition: def, value: $value)
        default:
            LabeledContent(definition.name) {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}

private struct CompositeFieldLink: View {
    let label: String
    let definition: CompositeTypeDefinition
    @Binding var value: StoredValue?

    var body: some View {
        NavigationLink {
            CompositeEditView(definition: definition, value: $value)
        } label: {
            LabeledContent(definition.decoratedLabel(label)) {
                let summary = value?.compositeSummary(for: definition) ?? ""
                Text(summary.isEmpty ? "—" : summary)
                    .foregroundStyle(summary.isEmpty ? .tertiary : .secondary)
            }
        }
    }
}

private struct ContactEditRow: View {
    let label: String
    @Binding var value: StoredValue?
    @State private var pickerPresented = false

    private var identifier: String? {
        if case .contact(let s) = value { return s }
        return nil
    }

    private var resolvedName: String? {
        guard let id = identifier else { return nil }
        return ContactResolver.shared.displayName(for: id)
    }

    var body: some View {
        LabeledContent(label) {
            if identifier != nil {
                HStack(spacing: 12) {
                    if let name = resolvedName {
                        Text(name).foregroundStyle(.secondary)
                    } else {
                        Text("(not found)").foregroundStyle(.tertiary)
                    }
                    Button { pickerPresented = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .buttonStyle(.borderless)
                    Button { value = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } else {
                Button { pickerPresented = true } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .background(
            ContactPicker(isPresented: $pickerPresented) { id, _ in
                value = .contact(id)
            }
        )
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
