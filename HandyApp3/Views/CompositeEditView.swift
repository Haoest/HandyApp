import SwiftUI

/// The full editor for a composite value (2D Size, and anything the user defines). Pushed from
/// the Specs tab, whose inline part inputs cover only text/number/currency — every other kind
/// of sub-field is reachable only here, which is why this screen dispatches on all of them.
///
/// Edits are held in a local working copy and pushed back to `value` as a single
/// `.composite(...)` on disappear, so a half-filled composite never reaches the bound setter
/// (which, for a thing's property, runs store validation requiring all required fields).
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

    private var summary: String {
        StoredValue.composite(working).compositeSummary(for: definition)
    }

    var body: some View {
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Field")
            VStack(alignment: .leading, spacing: 8) {
                Text(BuiltInTypes.localizedSeedName(id: definition.id, currentName: definition.name))
                    .font(Baron.heading(28))
                    .foregroundStyle(Baron.text)
                Text(summary.isEmpty ? String(localized: "Nothing filled in yet.", locale: .appPreferred) : summary)
                    .font(Baron.body(13))
                    .foregroundStyle(Baron.neutral600)
            }
            .padding(.top, 16)
            VStack(spacing: 8) {
                ForEach(definition.fields) { field in
                    CompositePartRow(field: field, value: binding(field.name))
                }
            }
            .padding(.top, 20)
            if !working.isEmpty {
                Button { working.removeAll() } label: {
                    Text("Clear all parts")
                        .font(Baron.heading(11.5))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Baron.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Baron.dangerBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .onDisappear {
            value = working.isEmpty ? nil : .composite(working)
        }
    }

    private func binding(_ name: String) -> Binding<StoredValue?> {
        Binding(
            get: { working[name] },
            set: { sub in
                if let sub { working[name] = sub } else { working.removeValue(forKey: name) }
            }
        )
    }
}

// MARK: - One part

/// A sub-field, wearing the same card as a Specs row but always open — there is only a handful
/// of them and they are the whole point of the screen, so nothing is worth collapsing.
private struct CompositePartRow: View {
    let field: PropertyDefinition
    @Binding var value: StoredValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(BuiltInTypes.localizedSeedName(id: field.id, currentName: field.name))
                    .font(Baron.body(10.5, .medium))
                    .tracking(0.85)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.neutral500)
                Spacer(minLength: 0)
                Text(field.type.displayName)
                    .font(Baron.body(10.5))
                    .foregroundStyle(Baron.neutral400)
            }
            editor
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .baronCard(radius: 15, elevation: .low)
    }

    @ViewBuilder
    private var editor: some View {
        switch field.type {
        case .basic(.text):
            PartTextEditor(kind: .text, maxLength: field.maxLength, value: $value)
        case .basic(.number):
            PartTextEditor(kind: .number, maxLength: nil, value: $value)
        case .basic(.currency):
            PartTextEditor(kind: .currency, maxLength: nil, value: $value)
        case .basic(.date):
            PartDateEditor(value: $value)
        case .basic(.contact):
            PartContactEditor(value: $value)
        case .comboList(let list):
            PartComboEditor(list: list, maxLength: field.maxLength, value: $value)
        default:
            // Composites don't nest and `.data` is photo payload, so nothing lands here today.
            Text("This part can't be edited here.")
                .font(Baron.body(12.5))
                .foregroundStyle(Baron.neutral600)
        }
    }
}

// MARK: - Part editors

/// Text, number, and currency share one editor, as they do on the Specs tab: same keyboard
/// switch, same commit-on-blur, and the same rule that a draft which doesn't parse leaves the
/// stored value alone rather than wiping it.
private struct PartTextEditor: View {
    enum Kind { case text, number, currency }

    let kind: Kind
    let maxLength: Int?
    @Binding var value: StoredValue?

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(kind: Kind, maxLength: Int?, value: Binding<StoredValue?>) {
        self.kind = kind
        self.maxLength = maxLength
        self._value = value
        _draft = State(initialValue: Self.text(from: value.wrappedValue, kind: kind))
    }

    private static func text(from value: StoredValue?, kind: Kind) -> String {
        switch (kind, value) {
        case (.text, .text(let s)): return s
        case (.number, .number(let d)): return "\(d)"
        case (.currency, .currency(let d)): return "\(d)"
        default: return ""
        }
    }

    var body: some View {
        Group {
            if kind == .text {
                TextField("", text: $draft, axis: .vertical)
                    .limitLength(maxLength, text: $draft)
            } else {
                TextField("", text: $draft)
                    .keyboardType(.decimalPad)
            }
        }
        .focused($isFocused)
        .onSubmit { commit() }
        .commitsPendingEdit(focused: isFocused) { commit() }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            draft = Self.text(from: newValue, kind: kind)
        }
        .specField()
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { value = nil; return }
        switch kind {
        case .text: value = .text(trimmed)
        case .number: if let d = Double(trimmed) { value = .number(d) }
        case .currency: if let d = Decimal(string: trimmed) { value = .currency(d) }
        }
    }
}

private struct PartDateEditor: View {
    @Binding var value: StoredValue?

    private var current: Date? {
        if case .date(let d) = value { return d }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            DatePicker(
                "",
                selection: Binding(get: { current ?? Date() }, set: { value = .date($0) }),
                displayedComponents: .date
            )
            .labelsHidden()
            if current != nil {
                Button("Clear") { value = nil }
                    .font(Baron.body(12, .medium))
                    .foregroundStyle(Baron.accent800)
            }
        }
    }
}

private struct PartContactEditor: View {
    @Binding var value: StoredValue?
    @State private var pickerPresented = false

    private var identifier: String? {
        if case .contact(let s) = value { return s }
        return nil
    }

    private var name: String? {
        identifier.flatMap { ContactResolver.shared.displayName(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let identifier {
                Text(name ?? String(localized: "(not found)", locale: .appPreferred))
                    .font(Baron.body(14, .medium))
                    .foregroundStyle(name == nil ? Baron.neutral500 : Baron.text)
                    .id(identifier)
            }
            HStack(spacing: 7) {
                action(identifier == nil ? "Choose contact" : "Change") { pickerPresented = true }
                if identifier != nil {
                    action("Clear", tint: Baron.danger) { value = nil }
                }
            }
        }
        .background(
            ContactPicker(isPresented: $pickerPresented) { id, _ in
                value = .contact(id)
            }
        )
    }

    private func action(_ title: LocalizedStringKey, tint: Color = Baron.accent800,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(Baron.body(12, .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Baron.surface, in: RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                    .strokeBorder(Baron.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Chips plus a free-text field, the same shape the Specs tab uses for a pick-list field.
///
/// Writes go to the parent's working dictionary rather than through `AssetStore`, so the
/// auto-add that normally happens on the way into the store has to be invoked here — without
/// it, typing an off-list answer inside a composite would be the one place in the app where a
/// new value doesn't join its list.
private struct PartComboEditor: View {
    @Environment(AssetStore.self) private var store
    let list: ComboListDefinition
    let maxLength: Int?
    @Binding var value: StoredValue?

    private var current: String {
        if case .text(let s) = value { return s }
        return ""
    }

    private var options: [String] {
        guard let maxLength else { return list.allOptions }
        return list.allOptions.filter { $0.count <= maxLength }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = option == current
                    Button { write(selected ? nil : option) } label: {
                        Text(option)
                            .font(Baron.body(12, .medium))
                            .foregroundStyle(selected ? Color.white : Baron.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? Baron.fill : Baron.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            if list.isUserExtensible {
                ComboListField(list: list, current: current, maxLength: maxLength,
                               showsSuggestions: false, prompt: "Something else") { newValue in
                    write(newValue)
                }
            }
        }
    }

    private func write(_ option: String?) {
        guard let option else { value = nil; return }
        let stored = StoredValue.text(option)
        store.handleComboListAutoAdd(stored: stored, type: .comboList(list))
        value = stored
    }
}
