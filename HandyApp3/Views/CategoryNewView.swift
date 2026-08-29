import SwiftUI

/// The new-category sheet. Deliberately shaped like `CategoryEditorView` — same icon-and-name
/// header, same field rows with explicit ↑/↓/× buttons — so creating a category and editing one
/// afterwards are recognisably the same screen rather than two different idioms.
///
/// Nothing here touches the store until Save: the whole draft, fields included, lives in local
/// state, which is why the rows renumber `sortOrder` themselves instead of going through
/// `AssetStore`'s reorder methods.
struct CategoryNewView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var iconName: String
    @State private var properties: [AssetProperty]
    @State private var iconPickerPresented = false
    @State private var addPropertyPresented = false
    @State private var propertyToEdit: AssetProperty?
    @State private var showDuplicateNameAlert = false

    /// Creates an empty new-category form, or — when `duplicating` is provided —
    /// prefills the icon and properties from an existing category while leaving the
    /// name blank for the user to fill in.
    init(duplicating source: AssetCategory? = nil) {
        _name = State(initialValue: "")
        _iconName = State(initialValue: source?.iconName ?? "square.grid.2x2")
        _properties = State(initialValue: source?.liveTemplates.map { template in
            AssetProperty(
                definition: template.definition,
                value: template.value,
                sortOrder: template.sortOrder
            )
        } ?? [])
    }

    var body: some View {
        RecordSheetScaffold(
            title: "New category",
            saveLabel: "Create",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            onSave: save,
            dismissesOnSave: false
        ) {
            identity
            fieldsSection
            Text("These fields are copied into every thing filed here. You can add more to a single thing later.")
                .font(Baron.body(12))
                .foregroundStyle(Baron.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $iconPickerPresented) {
            IconPickerView(current: iconName) { chosen in
                iconName = chosen
                iconPickerPresented = false
            }
        }
        .sheet(isPresented: $addPropertyPresented) {
            PropertyEditView { definition, value in
                let sortOrder = SortOrdering.next(after: properties.map(\.sortOrder))
                properties.append(AssetProperty(definition: definition, value: value, sortOrder: sortOrder))
            }
        }
        .sheet(item: $propertyToEdit) { prop in
            PropertyEditView(existing: prop) { definition, value in
                prop.definition = definition
                prop.value = value
                prop.touch()
            }
        }
        .alert("Name already used", isPresented: $showDuplicateNameAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A category named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists.")
        }
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { iconPickerPresented = true } label: {
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Baron.accent800)
                    .frame(width: 64, height: 64)
                    .background(Baron.accent100, in: RoundedRectangle(cornerRadius: Baron.Radius.card, style: .continuous))
                    .baronShadow(.medium)
            }
            .buttonStyle(.plain)
            RecordField(label: "Name") {
                TextField("e.g. Appliance", text: $name)
                    .limitLength(TextLimits.categoryName, text: $name)
                    .recordInput()
            }
        }
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                RecordFieldLabel(text: "Template fields")
                Spacer(minLength: 0)
                Text("\(properties.count)")
                    .font(Baron.body(11.5, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
            VStack(spacing: 8) {
                ForEach(Array(properties.enumerated()), id: \.element.id) { index, prop in
                    row(prop, at: index)
                }
                if properties.isEmpty {
                    Text("No fields yet. Things filed here will start blank.")
                        .font(Baron.body(13))
                        .foregroundStyle(Baron.neutral600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .baronCard(radius: 15, elevation: .low)
                }
                Button { addPropertyPresented = true } label: {
                    Text("+ Add field")
                        .font(Baron.heading(11.5))
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(Baron.accent800)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Baron.neutral400))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ prop: AssetProperty, at index: Int) -> some View {
        HStack(spacing: 10) {
            Button { propertyToEdit = prop } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(prop.definition.name)
                        .font(Baron.body(14.5, .medium))
                        .foregroundStyle(Baron.text)
                        .lineLimit(1)
                    Text(prop.definition.type.displayName)
                        .font(Baron.body(11.5))
                        .foregroundStyle(Baron.neutral600)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if prop.definition.isRequired {
                Text("Required")
                    .font(Baron.body(9.5, .semibold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.accent800)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Baron.accent100, in: Capsule())
            }
            iconButton("chevron.up", enabled: index > 0) { move(from: index, by: -1) }
            iconButton("chevron.down", enabled: index < properties.count - 1) { move(from: index, by: 1) }
            iconButton("xmark", tint: Baron.danger) { properties.removeAll { $0.id == prop.id } }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .baronCard(radius: 15, elevation: .low)
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

    private func move(from index: Int, by offset: Int) {
        let destination = index + offset
        guard properties.indices.contains(destination) else { return }
        properties.swapAt(index, destination)
    }

    private func save() {
        // Renumbers to match `properties`' final array order — the order the user left it in
        // after any move — rather than trusting each row's carried-over `sortOrder` (stale
        // after a reorder, or a duplicated category's original values). Safe to renormalize
        // freely here, unlike `AssetStore`'s reorder methods: nothing has been saved or synced
        // yet, so there's no cross-device merge blast radius to minimize.
        let values = SortOrdering.normalized(count: properties.count)
        for (index, prop) in properties.enumerated() {
            prop.sortOrder = values[index]
        }
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
