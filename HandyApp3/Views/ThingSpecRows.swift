import SwiftUI
import UIKit
import Contacts

/// One property on the Thing detail screen's Specs tab: a collapsed summary row that expands
/// in place into the right editor for its type.
///
/// This is the redesign's answer to a note in the original UI audit — combo lists, composites,
/// and contacts each had their own ad hoc shape (inline pills / drill-in page / icon-button
/// row), so the screen read as a pile of unrelated controls. Here every type wears the same
/// collapsed row and differs only once opened.
struct ThingSpecRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let isExpanded: Bool
    let onToggle: () -> Void
    /// Custom fields only — renames the field itself rather than its value.
    var onEditLabel: (() -> Void)? = nil
    /// Custom fields only.
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label)
                            .font(Baron.body(10.5, .medium))
                            .tracking(0.85)
                            .textCase(.uppercase)
                            .foregroundStyle(Baron.neutral500)
                            .lineLimit(1)
                        Text(display.isEmpty ? "—" : display)
                            .font(Baron.body(15, .medium))
                            .foregroundStyle(display.isEmpty ? Baron.neutral500 : Baron.text)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Baron.accent800)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                editor
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                if onEditLabel != nil || onDelete != nil {
                    HStack(spacing: 7) {
                        if let onEditLabel {
                            secondaryButton("Rename field", action: onEditLabel)
                        }
                        if let onDelete {
                            secondaryButton("Remove field", tint: Baron.danger, action: onDelete)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .baronCard(radius: 15, elevation: .low)
    }

    // MARK: - Collapsed summary

    private var label: String {
        if case .composite(let definition) = property.definition.type {
            return definition.decoratedLabel(BuiltInTypes.localizedSeedName(id: property.definition.id, currentName: property.definition.name))
        }
        return BuiltInTypes.localizedSeedName(id: property.definition.id, currentName: property.definition.name)
    }

    private var display: String {
        guard let value = property.value else { return "" }
        switch property.definition.type {
        case .composite(let definition):
            return value.compositeSummary(for: definition)
        case .basic(.contact):
            guard case .contact(let identifier) = value else { return "" }
            return ContactResolver.shared.displayName(for: identifier) ?? String(localized: "(not found)", locale: .appPreferred)
        default:
            return value.shortDisplay
        }
    }

    // MARK: - Expanded editor

    @ViewBuilder
    private var editor: some View {
        switch property.definition.type {
        case .basic(.text):
            SpecTextEditor(assetID: assetID, property: property, kind: .text)
        case .basic(.number):
            SpecTextEditor(assetID: assetID, property: property, kind: .number)
        case .basic(.currency):
            SpecTextEditor(assetID: assetID, property: property, kind: .currency)
        case .basic(.date):
            SpecDateEditor(assetID: assetID, property: property)
        case .basic(.contact):
            SpecContactEditor(assetID: assetID, property: property)
        case .comboList(let list):
            SpecComboEditor(assetID: assetID, property: property, list: list)
        case .composite(let definition):
            SpecCompositeEditor(assetID: assetID, property: property, definition: definition)
        default:
            Text("This field type can't be edited here.")
                .font(Baron.body(12.5))
                .foregroundStyle(Baron.neutral600)
        }
    }

    private func secondaryButton(_ title: LocalizedStringKey, tint: Color = Baron.accent800, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Baron.body(12, .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                    .strokeBorder(Baron.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared field chrome

/// The recessed input the design uses inside an expanded row. Internal because the composite
/// editor pushed from these rows has to match them.
struct SpecFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Baron.body(14, .medium))
            .foregroundStyle(Baron.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Baron.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func specField() -> some View { modifier(SpecFieldBackground()) }
}

// MARK: - Text / number / currency

/// The three keyboard-entry basics share one editor; they differ only in keyboard and in how a
/// draft parses back into a `StoredValue`. Commit-on-blur and the "leave the stored value alone
/// when the draft doesn't parse" rule are carried over verbatim from the old detail rows — a
/// half-typed "-" must not wipe a stored number.
private struct SpecTextEditor: View {
    enum Kind { case text, number, currency }

    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let kind: Kind

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty, kind: Kind) {
        self.assetID = assetID
        self.property = property
        self.kind = kind
        _draft = State(initialValue: Self.text(from: property.value, kind: kind))
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
                    .limitLength(property.definition.maxLength, text: $draft)
            } else {
                TextField("", text: $draft)
                    .keyboardType(.decimalPad)
            }
        }
        .focused($isFocused)
        .onSubmit { commit() }
        .commitsPendingEdit(focused: isFocused) { commit() }
        .onChange(of: property.value) { _, newValue in
            guard !isFocused else { return }
            draft = Self.text(from: newValue, kind: kind)
        }
        .specField()
    }

    private func commit() {
        let newValue: StoredValue?
        switch kind {
        case .text:
            newValue = draft.isEmpty ? nil : .text(draft)
        case .number:
            if let d = Double(draft) { newValue = .number(d) }
            else if draft.isEmpty { newValue = nil }
            else { return }
        case .currency:
            if let d = Decimal(string: draft) { newValue = .currency(d) }
            else if draft.isEmpty { newValue = nil }
            else { return }
        }
        guard newValue != property.value else { return }
        write(newValue)
    }

    private func write(_ value: StoredValue?) {
        if let value {
            try? store.setPropertyValue(value, forDefinitionID: property.definition.id, onAssetID: assetID)
        } else {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        }
    }
}

// MARK: - Date

private struct SpecDateEditor: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty

    private var current: Date? {
        if case .date(let d) = property.value { return d }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            DatePicker(
                "",
                selection: Binding(
                    get: { current ?? Date() },
                    set: { try? store.setPropertyValue(.date($0), forDefinitionID: property.definition.id, onAssetID: assetID) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            if current != nil {
                Button("Clear") {
                    try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                }
                .font(Baron.body(12, .medium))
                .foregroundStyle(Baron.accent800)
            }
        }
    }
}

// MARK: - Contact

/// Expands to the actions the contact supports, exactly as the old contact row decided
/// them: a button appears only when that method exists on the resolved contact.
private struct SpecContactEditor: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty

    @State private var pickerPresented = false
    @State private var contact: CNContact?

    private var identifier: String? {
        if case .contact(let s) = property.value { return s }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let contact {
                HStack(spacing: 7) {
                    if let phone = contact.phoneNumbers.first?.value.stringValue {
                        action("Call") { open("tel:\(urlSafe(phone))") }
                        action("Text") { open("sms:\(urlSafe(phone))") }
                    }
                    if let email = contact.emailAddresses.first.map({ $0.value as String }) {
                        action("Email") { open("mailto:\(email)") }
                    }
                }
            }
            HStack(spacing: 7) {
                action(identifier == nil ? "Choose contact" : "Change") { pickerPresented = true }
                if identifier != nil {
                    action("Clear", tint: Baron.danger) {
                        try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                    }
                }
            }
        }
        .background(
            ContactPicker(isPresented: $pickerPresented) { id, _ in
                try? store.setPropertyValue(.contact(id), forDefinitionID: property.definition.id, onAssetID: assetID)
            }
        )
        .task(id: identifier) {
            guard let id = identifier else { contact = nil; return }
            contact = try? ContactResolver.shared.contact(for: id)
        }
    }

    private func action(_ title: LocalizedStringKey, tint: Color = Baron.accent800, perform: @escaping () -> Void) -> some View {
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

    private func urlSafe(_ phone: String) -> String {
        phone.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? phone
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Combo list

/// Option chips, plus the free-text field the old `ComboListField` provided. The design showed
/// chips alone, but a combo list here is extensible — typing a new value adds it to the list —
/// and dropping the field would quietly remove that.
private struct SpecComboEditor: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let list: ComboListDefinition

    private var current: String {
        if case .text(let s) = property.value { return s }
        return ""
    }

    private var options: [String] {
        guard let maxLength = property.definition.maxLength else { return list.allOptions }
        // Same rule as ComboListField: never offer a chip the field can't actually store.
        return list.allOptions.filter { $0.count <= maxLength }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = option == current
                    Button {
                        // Tapping the selected chip clears the field — the only way to unset a
                        // value without opening the keyboard.
                        write(selected ? nil : .text(option))
                    } label: {
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
            // Only where an off-list value can actually be stored. On a closed list the field
            // would revert whatever was typed, which reads as the app ignoring you.
            if list.isUserExtensible {
                ComboListField(
                    list: list,
                    current: current,
                    maxLength: property.definition.maxLength,
                    showsSuggestions: false,
                    prompt: "Something else"
                ) { newValue in
                    write(newValue.map(StoredValue.text))
                }
            }
        }
    }

    private func write(_ value: StoredValue?) {
        if let value {
            try? store.setPropertyValue(value, forDefinitionID: property.definition.id, onAssetID: assetID)
        } else {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        }
    }
}

// MARK: - Composite

/// Inline part inputs for the basics a composite is normally built from, with a push to the
/// full `CompositeEditView` beneath. A user-defined composite may hold a date, contact, or
/// combo-list field that has no sensible inline shape — those are what the link is for, so no
/// sub-field is ever unreachable.
///
/// The parts are accumulated here before the store sees any of them. `AssetStore.validate`
/// rejects a composite that is missing a required part, and 2D Size requires both Width and
/// Length — so writing each part through as it was typed meant every write was refused and
/// nothing could ever be entered, since the first number could never be stored on its own.
private struct SpecCompositeEditor: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let definition: CompositeTypeDefinition

    /// Parts typed so far, including a set the store won't accept yet. Seeded from the stored
    /// value and re-seeded when that changes underneath us (a sync, or an edit made on the
    /// pushed screen).
    @State private var working: [String: StoredValue]

    init(assetID: UUID, property: AssetProperty, definition: CompositeTypeDefinition) {
        self.assetID = assetID
        self.property = property
        self.definition = definition
        _working = State(initialValue: Self.parts(of: property.value))
    }

    private static func parts(of value: StoredValue?) -> [String: StoredValue] {
        if case .composite(let dict) = value { return dict }
        return [:]
    }

    private var valueBinding: Binding<StoredValue?> {
        Binding(
            get: { working.isEmpty ? nil : .composite(working) },
            set: { newValue in
                working = Self.parts(of: newValue)
                push()
            }
        )
    }

    private var inlineFields: [PropertyDefinition] {
        definition.fields.filter { field in
            switch field.type {
            case .basic(.text), .basic(.number), .basic(.currency): return true
            default: return false
            }
        }
    }

    /// Required parts with nothing in them. While this is non-empty the store refuses the whole
    /// value, so the row says which part is holding it up rather than looking broken.
    private var missingRequired: [String] {
        definition.fields
            .filter { $0.isRequired && working[$0.name] == nil }
            .map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !inlineFields.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(inlineFields) { field in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(BuiltInTypes.localizedSeedName(id: field.id, currentName: field.name))
                                .font(Baron.body(9.5, .medium))
                                .tracking(0.85)
                                .textCase(.uppercase)
                                .foregroundStyle(Baron.neutral500)
                                .lineLimit(1)
                            CompositePartField(field: field, value: working[field.name]) { sub in
                                set(field.name, to: sub)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !working.isEmpty, !missingRequired.isEmpty {
                Text("Add \(missingRequired.formatted(.list(type: .and))) to save this.")
                    .font(Baron.body(11.5))
                    .foregroundStyle(Baron.accent800)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink {
                CompositeEditView(definition: definition, value: valueBinding)
            } label: {
                Text(inlineFields.count == definition.fields.count ? "All fields" : "More fields")
                    .font(Baron.body(12, .medium))
                    .foregroundStyle(Baron.accent800)
            }
        }
        .onChange(of: property.value) { _, newValue in
            let stored = Self.parts(of: newValue)
            // Only adopt a change that didn't come from here. A refused write leaves the stored
            // value behind the draft, and re-seeding from it would wipe what was just typed.
            guard stored != working, !stored.isEmpty || working.isEmpty else { return }
            working = stored
        }
    }

    private func set(_ name: String, to sub: StoredValue?) {
        if let sub { working[name] = sub } else { working.removeValue(forKey: name) }
        push()
    }

    /// Attempts the whole composite. An incomplete one throws — that is expected mid-entry, and
    /// the parts stay in `working` so the next part completes it.
    private func push() {
        if working.isEmpty {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        } else {
            try? store.setPropertyValue(.composite(working), forDefinitionID: property.definition.id, onAssetID: assetID)
        }
    }
}

private struct CompositePartField: View {
    let field: PropertyDefinition
    let value: StoredValue?
    let onCommit: (StoredValue?) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(field: PropertyDefinition, value: StoredValue?, onCommit: @escaping (StoredValue?) -> Void) {
        self.field = field
        self.value = value
        self.onCommit = onCommit
        _draft = State(initialValue: Self.text(from: value))
    }

    private static func text(from value: StoredValue?) -> String {
        switch value {
        case .text(let s): return s
        case .number(let d): return "\(d)"
        case .currency(let d): return "\(d)"
        default: return ""
        }
    }

    var body: some View {
        TextField("", text: $draft)
            .keyboardType(field.type == .basic(.text) ? .default : .decimalPad)
            .focused($isFocused)
            .onSubmit { commit() }
            .commitsPendingEdit(focused: isFocused) { commit() }
            .onChange(of: value) { _, newValue in
                guard !isFocused else { return }
                draft = Self.text(from: newValue)
            }
            .specField()
    }

    private func commit() {
        let sub: StoredValue?
        switch field.type {
        case .basic(.number):
            if let d = Double(draft) { sub = .number(d) }
            else if draft.isEmpty { sub = nil }
            else { return }
        case .basic(.currency):
            if let d = Decimal(string: draft) { sub = .currency(d) }
            else if draft.isEmpty { sub = nil }
            else { return }
        default:
            sub = draft.isEmpty ? nil : .text(draft)
        }
        guard sub != value else { return }
        onCommit(sub)
    }
}
