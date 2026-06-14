import SwiftUI
import UIKit
import Contacts

// MARK: - Property detail rows

struct PropertyDetailRow: View {
    let assetID: UUID
    let property: AssetProperty
    var onEditLabel: (() -> Void)? = nil

    var body: some View {
        switch property.definition.type {
        case .basic(.text):
            TextDetailField(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.contact):
            ContactDetailRow(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.number):
            NumberDetailField(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.currency):
            CurrencyDetailField(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .basic(.date):
            DateDetailRow(assetID: assetID, property: property, onEditLabel: onEditLabel)
        case .comboList(let list):
            ComboListDetailRow(assetID: assetID, property: property, list: list, onEditLabel: onEditLabel)
        case .composite(let def):
            CompositeDetailLink(assetID: assetID, property: property, definition: def, onEditLabel: onEditLabel)
        default:
            LabeledContent {
                Text("—").foregroundStyle(.tertiary)
            } label: {
                if let onEditLabel {
                    Button(property.definition.name) { onEditLabel() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                } else {
                    Text(property.definition.name)
                }
            }
        }
    }
}

private struct ContactDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var pickerPresented = false
    @State private var resolvedContact: CNContact?

    private var identifier: String? {
        if case .contact(let s) = property.value { return s }
        return nil
    }

    private var resolvedName: String? {
        guard let id = identifier else { return nil }
        return ContactResolver.shared.displayName(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabeledContent {
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
                        Button {
                            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                        } label: {
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
            } label: {
                if let onEditLabel {
                    Button(property.definition.name) { onEditLabel() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                } else {
                    Text(property.definition.name)
                }
            }

            if let contact = resolvedContact {
                ContactActionBar(contact: contact)
            }
        }
        .background(
            ContactPicker(isPresented: $pickerPresented) { id, _ in
                try? store.setPropertyValue(.contact(id), forDefinitionID: property.definition.id, onAssetID: assetID)
            }
        )
        .task(id: identifier) {
            guard let id = identifier else { resolvedContact = nil; return }
            resolvedContact = try? ContactResolver.shared.contact(for: id)
        }
    }
}

private struct ContactActionBar: View {
    let contact: CNContact

    private var firstPhone: String? {
        contact.phoneNumbers.first?.value.stringValue
    }

    private var firstEmail: String? {
        contact.emailAddresses.first.map { $0.value as String }
    }

    private var whatsAppPhone: String? {
        let hasWhatsApp = contact.instantMessageAddresses.contains {
            $0.value.service.lowercased() == "whatsapp"
        }
        guard hasWhatsApp, let phone = firstPhone else { return nil }
        return phone.filter { $0.isNumber || $0 == "+" }
    }

    var body: some View {
        HStack(spacing: 28) {
            if let phone = firstPhone {
                actionButton(systemImage: "phone.fill", color: .accentColor) {
                    open("tel:\(phone.filter { $0.isNumber || $0 == "+" })")
                }
                actionButton(systemImage: "message.fill", color: .accentColor) {
                    open("sms:\(phone.filter { $0.isNumber || $0 == "+" })")
                }
            }
            if let email = firstEmail {
                actionButton(systemImage: "envelope.fill", color: .accentColor) {
                    open("mailto:\(email)")
                }
            }
            if let number = whatsAppPhone {
                actionButton(systemImage: "phone.fill", color: .green) {
                    open("whatsapp://call?phone=\(number)")
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func actionButton(systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct TextDetailField: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty, onEditLabel: (() -> Void)? = nil) {
        self.assetID = assetID
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
                    if case .text(let s) = newValue { text = s } else { text = "" }
                }
        } label: {
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }

    private func commit() {
        if text.isEmpty {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        } else {
            try? store.setPropertyValue(.text(text), forDefinitionID: property.definition.id, onAssetID: assetID)
        }
    }
}

private struct NumberDetailField: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty, onEditLabel: (() -> Void)? = nil) {
        self.assetID = assetID
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
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }

    private func commit() {
        if let d = Double(text) {
            try? store.setPropertyValue(.number(d), forDefinitionID: property.definition.id, onAssetID: assetID)
        } else if text.isEmpty {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        }
    }
}

private struct CurrencyDetailField: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(assetID: UUID, property: AssetProperty, onEditLabel: (() -> Void)? = nil) {
        self.assetID = assetID
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
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }

    private func commit() {
        if let d = Decimal(string: text) {
            try? store.setPropertyValue(.currency(d), forDefinitionID: property.definition.id, onAssetID: assetID)
        } else if text.isEmpty {
            try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
        }
    }
}

private struct CompositeDetailLink: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let definition: CompositeTypeDefinition
    let onEditLabel: (() -> Void)?

    private var valueBinding: Binding<StoredValue?> {
        Binding(
            get: { property.value },
            set: { newValue in
                if let newValue {
                    try? store.setPropertyValue(newValue, forDefinitionID: property.definition.id, onAssetID: assetID)
                } else {
                    try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                }
            }
        )
    }

    var body: some View {
        // The trailing summary is the NavigationLink (drill-in to edit values); the
        // label stays a rename Button for custom properties. Keeping them as separate
        // tap targets avoids nesting a Button inside a NavigationLink.
        LabeledContent {
            NavigationLink {
                CompositeEditView(definition: definition, value: valueBinding)
            } label: {
                let summary = property.value?.compositeSummary(for: definition) ?? ""
                Text(summary.isEmpty ? "—" : summary)
                    .foregroundStyle(summary.isEmpty ? .tertiary : .secondary)
            }
        } label: {
            let title = definition.decoratedLabel(property.definition.name)
            if let onEditLabel {
                Button(title) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(title)
            }
        }
    }
}

private struct DateDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let onEditLabel: (() -> Void)?

    private var dateBinding: Binding<Date> {
        Binding(
            get: { if case .date(let d) = property.value { return d }; return Date() },
            set: { date in try? store.setPropertyValue(.date(date), forDefinitionID: property.definition.id, onAssetID: assetID) }
        )
    }

    var body: some View {
        LabeledContent {
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
        } label: {
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }
}

private struct ComboListDetailRow: View {
    @Environment(AssetStore.self) private var store
    let assetID: UUID
    let property: AssetProperty
    let list: ComboListDefinition
    let onEditLabel: (() -> Void)?

    private var selectionBinding: Binding<String> {
        Binding(
            get: { if case .text(let s) = property.value { return s }; return "" },
            set: { option in
                if option.isEmpty {
                    try? store.removePropertyValue(forDefinitionID: property.definition.id, fromAssetID: assetID)
                } else {
                    try? store.setPropertyValue(.text(option), forDefinitionID: property.definition.id, onAssetID: assetID)
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
            if let onEditLabel {
                Button(property.definition.name) { onEditLabel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            } else {
                Text(property.definition.name)
            }
        }
    }
}
