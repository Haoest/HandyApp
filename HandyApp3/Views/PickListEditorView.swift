import SwiftUI

/// The pick-list editor. Replaces `ComboListDetailView`.
///
/// The old screen edited one option at a time through a single field at the bottom whose
/// placeholder flipped between "Add option" and "Edit option" — you had to tap a row to load it
/// in, then find the field again. Here every value is its own always-editable row, and the
/// built-in ones are visibly locked rather than merely refusing to change.
struct PickListEditorView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let list: ComboListDefinition

    @State private var newOption = ""
    @State private var addFieldPresented = false
    @State private var deleteConfirmationPresented = false
    @State private var duplicateNameAlertPresented = false
    @FocusState private var newOptionFocused: Bool

    private var references: [ComboListReference] {
        ComboListUsage.references(toComboListID: list.id,
                                 categories: store.allCategories,
                                 assets: store.allAssets)
    }

    var body: some View {
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Pick lists") {
                Text("^[\(references.count) field](inflect: true)")
                    .font(Baron.body(11.5, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
            nameSection.padding(.top, 18)
            valuesSection.padding(.top, 22)
            freeformCard.padding(.top, 18)
            if !references.isEmpty { usedBySection.padding(.top, 18) }
            deleteButton.padding(.top, 14)
        }
        .confirmationDialog("Delete \"\(list.name)\"?", isPresented: $deleteConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Delete pick list", role: .destructive) {
                try? store.softDeleteComboList(id: list.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Things already using this list keep their stored values — it only disappears from future pickers, and you can restore it from Deleted items.")
        }
        .alert("Name already used", isPresented: $duplicateNameAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Another pick list already has that name.")
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("List name")
                .font(Baron.body(10.5, .medium))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral500)
            PickListNameEditor(list: list, onDuplicate: { duplicateNameAlertPresented = true })
        }
    }

    // MARK: - Values

    private var valuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Values")
                    .font(Baron.body(10.5, .medium))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.neutral500)
                Spacer(minLength: 0)
                Text("\(list.allOptions.count)")
                    .font(Baron.body(11.5, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
            VStack(spacing: 8) {
                ForEach(Array(list.systemOptions.enumerated()), id: \.element) { index, option in
                    systemRow(number: index + 1, option: option)
                }
                ForEach(Array(list.userOptions.enumerated()), id: \.element) { index, option in
                    PickListValueRow(
                        number: list.systemOptions.count + index + 1,
                        option: option,
                        listID: list.id,
                        usageCount: ComboListUsage.storedValueCount(of: option, listID: list.id, assets: store.allAssets),
                        canMoveUp: index > 0,
                        canMoveDown: index < list.userOptions.count - 1
                    )
                }
                addRow
            }
            if !list.systemOptions.isEmpty {
                Text("Built-in values can't be renamed or removed — they're what the app seeded the list with.")
                    .font(Baron.body(12))
                    .foregroundStyle(Baron.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func systemRow(number: Int, option: String) -> some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(Baron.body(11, .medium))
                .foregroundStyle(Baron.neutral400)
                .frame(minWidth: 14, alignment: .trailing)
            Text(option)
                .font(Baron.body(14, .medium))
                .foregroundStyle(Baron.neutral600)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(Baron.neutral400)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 13)
        .baronCard(radius: 14, elevation: .low)
    }

    private var addRow: some View {
        HStack(spacing: 9) {
            TextField("Add a value", text: $newOption)
                .font(Baron.body(14, .medium))
                .foregroundStyle(Baron.text)
                .focused($newOptionFocused)
                .onSubmit { commitNewOption() }
                .limitLength(TextLimits.comboListOption, text: $newOption)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(Baron.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Button { commitNewOption() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(newOption.trimmingCharacters(in: .whitespaces).isEmpty ? Baron.neutral400 : Baron.accent800)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                        .strokeBorder(Baron.neutral300, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .baronCard(radius: 14, elevation: .low)
    }

    private func commitNewOption() {
        let trimmed = newOption.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? store.addUserOption(trimmed, toComboListID: list.id)
        newOption = ""
    }

    // MARK: - Off-list answers

    private var freeformCard: some View {
        Button {
            try? store.setComboListExtensible(id: list.id, !list.isUserExtensible)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow off-list answers")
                        .font(Baron.body(14.5, .medium))
                        .foregroundStyle(Baron.text)
                    Text(list.isUserExtensible
                         ? "Typing a new value adds it to this list."
                         : "Only the values above can be chosen. Anything already stored is left as it is.")
                        .font(Baron.body(11.5))
                        .foregroundStyle(Baron.neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ToggleTrack(isOn: list.isUserExtensible)
            }
            .padding(15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .baronCard(elevation: .low)
    }

    // MARK: - Used by

    private var usedBySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Used by")
                .font(Baron.body(10.5, .medium))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral500)
            VStack(spacing: 0) {
                ForEach(Array(references.enumerated()), id: \.element.id) { index, reference in
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reference.fieldName)
                                    .font(Baron.body(14, .medium))
                                    .foregroundStyle(Baron.text)
                                Text(reference.isTemplate
                                     ? String(localized: "Template field on \(reference.ownerName)")
                                     : String(localized: "Custom field on \(reference.ownerName)"))
                                    .font(Baron.body(11.5))
                                    .foregroundStyle(Baron.neutral600)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        if index < references.count - 1 {
                            Baron.line.frame(height: 1).padding(.leading, 15)
                        }
                    }
                }
            }
            .baronCard(elevation: .low)
        }
    }

    private var deleteButton: some View {
        Button { deleteConfirmationPresented = true } label: {
            Text("Delete pick list")
                .font(Baron.heading(11.5))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Baron.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Baron.dangerBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Name field

private struct PickListNameEditor: View {
    @Environment(AssetStore.self) private var store
    let list: ComboListDefinition
    let onDuplicate: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(list: ComboListDefinition, onDuplicate: @escaping () -> Void) {
        self.list = list
        self.onDuplicate = onDuplicate
        _text = State(initialValue: list.name)
    }

    var body: some View {
        TextField("Name", text: $text)
            .font(Baron.body(16, .medium))
            .foregroundStyle(Baron.text)
            .focused($isFocused)
            .onSubmit { commit() }
            .commitsPendingEdit(focused: isFocused) { commit() }
            .limitLength(TextLimits.comboListName, text: $text)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .baronCard(radius: Baron.Radius.field, elevation: .low)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { text = list.name; return }
        guard trimmed != list.name else { return }
        guard store.comboListNameIsAvailable(trimmed, excluding: list.id) else {
            text = list.name
            onDuplicate()
            return
        }
        try? store.updateComboList(id: list.id, name: trimmed)
    }
}

// MARK: - Value row

/// One user-added value. Renaming commits on blur through `renameUserOption`, which holds the
/// option's position — a remove-then-append would send an edited value to the bottom of the
/// list, which is exactly why that store method exists.
private struct PickListValueRow: View {
    @Environment(AssetStore.self) private var store

    let number: Int
    let option: String
    let listID: UUID
    let usageCount: Int
    let canMoveUp: Bool
    let canMoveDown: Bool

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(number: Int, option: String, listID: UUID, usageCount: Int, canMoveUp: Bool, canMoveDown: Bool) {
        self.number = number
        self.option = option
        self.listID = listID
        self.usageCount = usageCount
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        _draft = State(initialValue: option)
    }

    var body: some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(Baron.body(11, .medium))
                .foregroundStyle(Baron.neutral400)
                .frame(minWidth: 14, alignment: .trailing)
            TextField("Value", text: $draft)
                .font(Baron.body(14, .medium))
                .foregroundStyle(Baron.text)
                .focused($isFocused)
                .onSubmit { commit() }
                .commitsPendingEdit(focused: isFocused) { commit() }
                .limitLength(TextLimits.comboListOption, text: $draft)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(Baron.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if usageCount > 0 {
                Text("\(usageCount)")
                    .font(Baron.body(10.5))
                    .foregroundStyle(Baron.neutral500)
            }
            iconButton("chevron.up", enabled: canMoveUp) {
                try? store.moveUserOption(option, inComboListID: listID, by: -1)
            }
            iconButton("chevron.down", enabled: canMoveDown) {
                try? store.moveUserOption(option, inComboListID: listID, by: 1)
            }
            iconButton("xmark", tint: Baron.danger) {
                try? store.removeUserOption(option, fromComboListID: listID)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .baronCard(radius: 14, elevation: .low)
        .onChange(of: option) { _, newValue in
            guard !isFocused else { return }
            draft = newValue
        }
    }

    private func iconButton(_ systemName: String, enabled: Bool = true, tint: Color = Baron.neutral600,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? tint : Baron.neutral300)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Baron.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { draft = option; return }
        guard trimmed != option else { return }
        try? store.renameUserOption(option, to: trimmed, inComboListID: listID)
    }
}
