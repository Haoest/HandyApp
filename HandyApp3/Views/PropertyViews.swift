import SwiftUI
import UIKit

// MARK: - Field editor

/// The field sheet: name, type, character bound, and an optional starting value. Reached from
/// the category editor ("+ Add field" and each row's "Type & default value") and from a thing's
/// Specs tab ("+ Custom field"), which makes it the most-travelled editor in the app.
///
/// The type picker is the substantive change from the old `Form`. It used to be a menu listing
/// the basics, the composites, and one "Combo list" row that revealed a *second* menu naming
/// the list — two taps and a hidden dependency between them. Here every type is a chip, pick
/// lists included, so choosing "Condition" is one tap and the full set is visible at a glance.
struct PropertyEditView: View {
    @Environment(AssetStore.self) private var store

    let existing: AssetProperty?
    let onSave: (PropertyDefinition, StoredValue?) -> Void

    /// One case per chip. `.composite`/`.comboList` carry the definition's id rather than the
    /// definition, so a selection stays valid if `store.allCompositeTypes` /
    /// `allComboListDefinitions` change while the sheet is open.
    private enum TypeChoice: Hashable {
        case basic(BasicType)
        case composite(UUID)
        case comboList(UUID)
    }

    init(existing: AssetProperty? = nil, onSave: @escaping (PropertyDefinition, StoredValue?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.definition.name ?? "")
        _isRequired = State(initialValue: existing?.definition.isRequired ?? true)
        _maxLengthText = State(initialValue: existing?.definition.maxLength.map(String.init)
                                ?? String(PropertyDefinition.defaultTextMaxLength))
        if case .comboList(let list) = existing?.definition.type {
            _typeChoice = State(initialValue: .comboList(list.id))
            _originalComboList = State(initialValue: list)
        } else if case .composite(let ct) = existing?.definition.type {
            _typeChoice = State(initialValue: .composite(ct.id))
        } else if case .basic(let b) = existing?.definition.type {
            _typeChoice = State(initialValue: .basic(b))
        }
    }

    @State private var name: String
    @State private var isRequired: Bool
    @State private var maxLengthText: String
    @State private var typeChoice: TypeChoice = .basic(.text)
    /// Captured from `existing` at init so a field typed on a since-deleted pick list still has
    /// its list available to show — otherwise the selected chip wouldn't be among the chips.
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

    /// Resolved from the raw store dicts (not the `all…` arrays) so a field already typed on a
    /// deleted definition still resolves.
    private var currentType: PropertyType? {
        switch typeChoice {
        case .basic(let b):
            return .basic(b)
        case .composite(let id):
            return store.compositeTypes[id].map { .composite($0) }
        case .comboList(let id):
            if let list = store.comboListDefinitions[id] { return .comboList(list) }
            if let originalComboList, originalComboList.id == id { return .comboList(originalComboList) }
            return nil
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
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
        return Array(completions.prefix(6))
    }

    private var enteredValue: StoredValue? {
        switch currentType {
        case .basic(.text):
            return valueText.isEmpty ? nil : .text(valueText)
        case .basic(.contact):
            return valueContactID.isEmpty ? nil : .contact(valueContactID)
        case .basic(.number):
            return NumberParsing.double(valueText).map { .number($0) }
        case .basic(.currency):
            return NumberParsing.decimal(valueText).map { .currency($0) }
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

    /// Whether the selected type takes a character bound — `.basic(.text)` or `.comboList`,
    /// mirroring `PropertyDefinition.acceptsMaxLength`.
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

    private var canSave: Bool {
        !trimmedName.isEmpty && currentType != nil && !(typeTakesMaxLength && parsedMaxLength == nil)
    }

    var body: some View {
        RecordSheetScaffold(
            title: existing == nil ? "New field" : "Edit field",
            saveLabel: "Save",
            canSave: canSave,
            onSave: save
        ) {
            nameField
            typeField
            if typeTakesMaxLength { lengthField }
            requiredCard
            if hasEditableValue {
                RecordField(label: existing == nil ? "Starting value" : "Value") { valueField }
            } else if case .composite = currentType {
                RecordNote(text: "A structured field is filled in on the thing itself, one part at a time.")
            }
        }
        .onAppear { prepopulate() }
        .background(
            ContactPicker(isPresented: $contactPickerPresented) { id, name in
                valueContactID = id
                valueContactName = name
            }
        )
    }

    private func save() {
        guard let type = currentType else { return }
        let def = PropertyDefinition(
            name: trimmedName,
            type: type,
            isRequired: isRequired,
            maxLength: typeTakesMaxLength ? parsedMaxLength : nil
        )
        onSave(def, enteredValue)
    }

    // MARK: - Name

    private var nameField: some View {
        RecordField(label: "Field name") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("e.g. Serial number", text: $name)
                    .focused($nameFieldFocused)
                    .autocorrectionDisabled()
                    .limitLength(TextLimits.propertyName, text: $name)
                    .recordInput()
                // Spelling completions for the word being typed. They were list rows before,
                // which pushed the rest of the form off-screen as you typed; as chips they sit
                // in one line under the field.
                if nameFieldFocused && !suggestions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button { complete(with: suggestion) } label: {
                                Text(suggestion)
                                    .font(Baron.body(12))
                                    .foregroundStyle(Baron.neutral700)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(Baron.inset, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func complete(with suggestion: String) {
        var parts = name.components(separatedBy: " ")
        parts[parts.count - 1] = suggestion
        name = parts.joined(separator: " ") + " "
    }

    // MARK: - Type

    private var typeField: some View {
        RecordField(label: "Type") {
            VStack(alignment: .leading, spacing: 12) {
                typeCluster(title: "Basics") {
                    ForEach(BasicType.userSelectable, id: \.self) { basic in
                        typeChip(basic.displayName, choice: .basic(basic))
                    }
                }
                if !sortedComposites.isEmpty {
                    typeCluster(title: "Structured") {
                        ForEach(sortedComposites) { ct in
                            typeChip(BuiltInTypes.localizedSeedName(id: ct.id, currentName: ct.name), choice: .composite(ct.id))
                        }
                    }
                }
                if comboListChoices.isEmpty {
                    Text("No pick lists yet. Make one in Setup › Pick lists to offer a fixed set of answers.")
                        .font(Baron.body(12))
                        .foregroundStyle(Baron.neutral500)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    typeCluster(title: "Pick lists") {
                        ForEach(comboListChoices) { list in
                            typeChip(BuiltInTypes.localizedSeedName(id: list.id, currentName: list.name), choice: .comboList(list.id))
                        }
                    }
                }
            }
        }
    }

    private func typeCluster<Chips: View>(title: LocalizedStringKey,
                                          @ViewBuilder chips: () -> Chips) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Baron.body(10.5, .medium))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral400)
            FlowLayout(spacing: 6) { chips() }
        }
    }

    private func typeChip(_ title: String, choice: TypeChoice) -> some View {
        let selected = typeChoice == choice
        return Button { pick(choice) } label: {
            Text(title)
                .font(Baron.body(12, .medium))
                .foregroundStyle(selected ? Color.white : Baron.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Baron.fill : Baron.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pick(_ choice: TypeChoice) {
        guard choice != typeChoice else { return }
        typeChoice = choice
        clearValue()
    }

    // MARK: - Length

    private var lengthField: some View {
        RecordField(label: "Max length") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("100", text: $maxLengthText)
                    .keyboardType(.numberPad)
                    .onChange(of: maxLengthText) { _, newValue in
                        let digitsOnly = newValue.filter(\.isNumber)
                        if digitsOnly != newValue { maxLengthText = digitsOnly }
                    }
                    .recordInput()
                Text("The most characters this field can hold, up to \(PropertyDefinition.systemMaxLength).")
                    .font(Baron.body(11.5))
                    .foregroundStyle(parsedMaxLength == nil ? Baron.danger : Baron.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Required

    private var requiredCard: some View {
        Button { isRequired.toggle() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required")
                        .font(Baron.body(15, .medium))
                        .foregroundStyle(Baron.text)
                    Text(isRequired
                         ? "Has to be filled in before the thing can be saved."
                         : "Can be left blank.")
                        .font(Baron.body(11.5))
                        .foregroundStyle(Baron.neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ToggleTrack(isOn: isRequired)
            }
            .contentShape(Rectangle())
            .padding(15)
            .baronCard(elevation: .low)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Value

    @ViewBuilder
    private var valueField: some View {
        switch currentType {
        case .basic(.text):
            TextField("Optional", text: $valueText)
                .limitLength(parsedMaxLength, text: $valueText)
                .recordInput()
        case .basic(.contact):
            Button { contactPickerPresented = true } label: {
                HStack(spacing: 8) {
                    if !valueContactName.isEmpty {
                        Text(valueContactName).foregroundStyle(Baron.text)
                    } else if !valueContactID.isEmpty {
                        Text("(not found)").foregroundStyle(Baron.neutral500)
                    } else {
                        Text("Choose a contact…").foregroundStyle(Baron.neutral500)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Baron.accent800)
                }
                .contentShape(Rectangle())
                .recordInput()
            }
            .buttonStyle(.plain)
        case .basic(.number), .basic(.currency):
            TextField("Optional", text: $valueText)
                .keyboardType(.decimalPad)
                .recordInput()
        case .basic(.date):
            VStack(alignment: .leading, spacing: 10) {
                Button { valueDateEnabled.toggle() } label: {
                    HStack(spacing: 10) {
                        Text("Set a date")
                            .font(Baron.body(13))
                            .foregroundStyle(Baron.neutral700)
                        Spacer(minLength: 0)
                        ToggleTrack(isOn: valueDateEnabled)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if valueDateEnabled {
                    DatePicker("", selection: $valueDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .baronCard(radius: Baron.Radius.field, elevation: .low)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .baronCard(elevation: .low)
        case .comboList(let list):
            ComboListField(list: list, current: valueCombo,
                           maxLength: parsedMaxLength) { newValue in
                valueCombo = newValue ?? ""
            }
        default:
            EmptyView()
        }
    }

    private func prepopulate() {
        guard let existing, let value = existing.value else { return }
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
