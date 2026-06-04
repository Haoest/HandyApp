import SwiftUI

struct CategoryNewView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var iconName = "square.grid.2x2"
    @State private var properties: [AssetProperty] = []
    @State private var iconPickerPresented = false
    @State private var addPropertyPresented = false
    @State private var propertyToEdit: AssetProperty?
    @State private var showDuplicateNameAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                }

                Section("Icon") {
                    Button {
                        iconPickerPresented = true
                    } label: {
                        HStack {
                            Image(systemName: iconName)
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: 32, height: 32)
                            Text(iconName)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    ForEach(properties) { prop in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prop.definition.name)
                                Text(prop.definition.type.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if prop.definition.isRequired {
                                Text("Required")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { propertyToEdit = prop }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                properties.removeAll { $0.id == prop.id }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        addPropertyPresented = true
                    } label: {
                        Label("Add Property", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Properties")
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $iconPickerPresented) {
                IconPickerView(current: iconName) { chosen in
                    iconName = chosen
                    iconPickerPresented = false
                }
            }
            .sheet(isPresented: $addPropertyPresented) {
                PropertyEditView { definition, value in
                    properties.append(AssetProperty(definition: definition, value: value))
                }
            }
            .sheet(item: $propertyToEdit) { prop in
                PropertyEditView(existing: prop) { definition, value in
                    if let idx = properties.firstIndex(where: { $0.id == prop.id }) {
                        properties[idx] = AssetProperty(
                            id: prop.id,
                            definition: definition,
                            value: value,
                            sortOrder: prop.sortOrder
                        )
                    }
                }
            }
            .alert("Duplicate Name", isPresented: $showDuplicateNameAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A category named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists.")
            }
        }
    }

    private func save() {
        do {
            try store.createCategory(
                name: name.trimmingCharacters(in: .whitespaces),
                iconName: iconName,
                propertyTemplates: properties
            )
            dismiss()
        } catch AssetStoreError.duplicateCategoryName {
            showDuplicateNameAlert = true
        } catch {}
    }
}
