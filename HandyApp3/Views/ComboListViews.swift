import SwiftUI

// MARK: - Combo list detail (rename, curate options, delete)

struct ComboListDetailView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let list: ComboListDefinition
    @State private var newOption: String = ""
    /// The user option currently loaded into `newOption` for editing, if any — tapping a row
    /// re-opens it here instead of appending a duplicate. Tracked by value, not index: the row
    /// list is store-backed and can reorder/shrink out from under a stale index.
    @State private var editingOption: String?
    @State private var deleteConfirmationPresented = false

    var body: some View {
        Form {
            Section {
                ComboListNameField(list: list)
            }

            Section {
                ForEach(list.systemOptions, id: \.self) { option in
                    HStack {
                        Text(option)
                        Spacer()
                        Image(systemName: "lock")
                            .foregroundStyle(.tertiary)
                    }
                }
                ForEach(list.userOptions, id: \.self) { option in
                    HStack {
                        Text(option)
                        if editingOption == option {
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing(option) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            try? store.removeUserOption(option, fromComboListID: list.id)
                            if editingOption == option { cancelEditing() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                HStack {
                    TextField(editingOption == nil ? "Add option" : "Edit option", text: $newOption)
                        .onSubmit { addOption() }
                        .limitLength(TextLimits.comboListOption, text: $newOption)
                    Button {
                        addOption()
                    } label: {
                        Image(systemName: editingOption == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    }
                    .disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Options")
            } footer: {
                if !list.systemOptions.isEmpty {
                    Text("Built-in options can't be removed.")
                }
            }

            Section {
                Button(role: .destructive) {
                    deleteConfirmationPresented = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Combo List")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete \"\(list.name)\"?",
            isPresented: $deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Combo List", role: .destructive) {
                try? store.softDeleteComboList(id: list.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The list will be hidden. Assets already using it keep their values.")
        }
    }

    private func beginEditing(_ option: String) {
        editingOption = option
        newOption = option
    }

    private func cancelEditing() {
        editingOption = nil
        newOption = ""
    }

    private func addOption() {
        let trimmed = newOption.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let editingOption {
            try? store.renameUserOption(editingOption, to: trimmed, inComboListID: list.id)
        } else {
            try? store.addUserOption(trimmed, toComboListID: list.id)
        }
        newOption = ""
        editingOption = nil
    }
}

private struct ComboListNameField: View {
    @Environment(AssetStore.self) private var store
    let list: ComboListDefinition
    @State private var text: String
    @State private var showDuplicateNameAlert = false
    @FocusState private var isFocused: Bool

    init(list: ComboListDefinition) {
        self.list = list
        _text = State(initialValue: list.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: "Name", onEditLabel: nil)
            TextField("Name", text: $text)
                .focused($isFocused)
                .onSubmit { commit() }
                .commitsPendingEdit(focused: isFocused) { commit() }
                .limitLength(TextLimits.comboListName, text: $text)
        }
        .alert("Duplicate Name", isPresented: $showDuplicateNameAlert) {
            Button("OK", role: .cancel) { text = list.name }
        } message: {
            Text("A combo list named \"\(text.trimmingCharacters(in: .whitespaces))\" already exists.")
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { text = list.name; return }
        guard trimmed != list.name else { return }
        guard store.comboListNameIsAvailable(trimmed, excluding: list.id) else {
            showDuplicateNameAlert = true
            return
        }
        try? store.updateComboList(id: list.id, name: trimmed)
    }
}

// MARK: - Summary row (Categories tab)

struct ComboListSummaryRow: View {
    let list: ComboListDefinition
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .foregroundStyle(.primary)
                    Text("^[\(list.allOptions.count) option](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
