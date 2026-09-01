import SwiftUI

/// The category editor. Replaces the old `Form`-based template screen.
///
/// Two things change beyond styling. Field rows carry explicit ↑/↓/× buttons instead of
/// drag-to-reorder and swipe-to-delete — the same discoverability argument the design makes
/// everywhere else. And "Update Existing Assets", which the audit called out as "a fairly
/// consequential bulk-mutation action buried as a plain list button", is now a card that only
/// appears when there is actually something to push, quoting the real diff.
struct CategoryEditorView: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let category: AssetCategory

    @State private var iconPickerPresented = false
    @State private var addPropertyPresented = false
    @State private var propertyToEdit: AssetProperty?
    @State private var expandedFieldID: UUID?
    @State private var deleteConfirmationPresented = false
    @State private var propagationResultMessage: LocalizedStringKey?

    /// `category.liveTemplates` sorted for display — `sortOrder` is what moves, never the
    /// backing array, so every render must re-sort rather than trust array order.
    private var sortedTemplates: [AssetProperty] {
        category.liveTemplates.sorted(by: SortOrdering.precedes)
    }

    private var thingCount: Int {
        store.allAssets.filter { $0.category.id == category.id }.count
    }

    /// Recomputed on every render so the card appears and disappears as the template is edited.
    private var pending: TemplatePropagationSummary {
        (try? store.previewTemplatePropagation(forCategoryID: category.id)) ?? .init()
    }

    var body: some View {
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Categories") {
                Text("^[\(thingCount) thing](inflect: true)")
                    .font(Baron.body(11.5, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
            identity.padding(.top, 18)
            fieldsSection.padding(.top, 22)
            if !pending.isEmpty {
                pendingCard.padding(.top, 16)
            }
            deleteButton.padding(.top, 14)
        }
        .sheet(isPresented: $iconPickerPresented) {
            IconPickerView(current: category.iconName) { newIcon in
                try? store.updateCategoryIcon(id: category.id, iconName: newIcon)
                iconPickerPresented = false
            }
        }
        .sheet(isPresented: $addPropertyPresented) {
            PropertyEditView { definition, value in
                try? store.appendTemplateProperty(definition: definition, value: value, toCategoryID: category.id)
            }
        }
        .sheet(item: $propertyToEdit) { prop in
            PropertyEditView(existing: prop) { definition, value in
                try? store.updateTemplateProperty(id: prop.id, inCategoryID: category.id,
                                                  name: definition.name, type: definition.type,
                                                  maxLength: definition.maxLength)
                if let value {
                    try? store.setTemplatePropertyValue(value, forPropertyID: prop.id, inCategoryID: category.id)
                } else {
                    try? store.removeTemplatePropertyValue(forPropertyID: prop.id, inCategoryID: category.id)
                }
            }
        }
        .confirmationDialog("Delete \"\(category.name)\"?", isPresented: $deleteConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Delete category", role: .destructive) {
                try? store.softDeleteCategory(id: category.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The category will be removed. Existing things will not be affected.")
        }
        .alert("Update existing things", isPresented: Binding(
            get: { propagationResultMessage != nil },
            set: { if !$0 { propagationResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { propagationResultMessage = nil }
        } message: {
            Text(propagationResultMessage ?? "")
        }
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { iconPickerPresented = true } label: {
                Image(systemName: category.iconName)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Baron.accent800)
                    .frame(width: 64, height: 64)
                    .background(Baron.accent100, in: RoundedRectangle(cornerRadius: Baron.Radius.card, style: .continuous))
                    .baronShadow(.medium)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 7) {
                Text("Name")
                    .font(Baron.body(10.5, .medium))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.neutral500)
                CategoryNameEditor(category: category)
            }
        }
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Template fields")
                    .font(Baron.body(10.5, .medium))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.neutral500)
                Spacer(minLength: 0)
                Text("\(sortedTemplates.count)")
                    .font(Baron.body(11.5, .medium))
                    .foregroundStyle(Baron.neutral600)
            }
            VStack(spacing: 8) {
                ForEach(Array(sortedTemplates.enumerated()), id: \.element.id) { index, property in
                    CategoryFieldRow(
                        categoryID: category.id,
                        property: property,
                        isExpanded: expandedFieldID == property.id,
                        canMoveUp: index > 0,
                        canMoveDown: index < sortedTemplates.count - 1,
                        onToggle: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                expandedFieldID = expandedFieldID == property.id ? nil : property.id
                            }
                        },
                        onMove: { offset in move(from: index, by: offset) },
                        onEditDetails: { propertyToEdit = property },
                        onRemove: {
                            try? store.removeTemplateProperty(id: property.id, fromCategoryID: category.id)
                        }
                    )
                }
                if sortedTemplates.isEmpty {
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
            Text("These values are copied into new things created from this category.")
                .font(Baron.body(12))
                .foregroundStyle(Baron.neutral500)
        }
    }

    /// `moveTemplateProperties` takes `.onMove` semantics, where moving down needs an index one
    /// past the target — the same off-by-one every SwiftUI list move has to account for.
    private func move(from index: Int, by offset: Int) {
        let destination = index + offset
        guard destination >= 0, destination < sortedTemplates.count else { return }
        let toOffset = offset > 0 ? destination + 1 : destination
        try? store.moveTemplateProperties(fromOffsets: IndexSet(integer: index),
                                          toOffset: toOffset, inCategoryID: category.id)
    }

    // MARK: - Propagation

    private var pendingCard: some View {
        let summary = pending
        return VStack(alignment: .leading, spacing: 0) {
            Text("Template changed")
                .font(Baron.heading(10.5))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Baron.accent800)
            Text("^[\(summary.affectedAssetCount) thing](inflect: true) would change")
                .font(Baron.heading(17))
                .foregroundStyle(Baron.text)
                .padding(.top, 9)
            Text("Existing things keep what they have until you push this across. Values you've already entered are kept wherever they still fit.")
                .font(Baron.body(12.5))
                .foregroundStyle(Baron.neutral600)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 6) {
                changeLine(count: summary.added, text: "^[\(summary.added) field](inflect: true) added")
                changeLine(count: summary.removed, text: "^[\(summary.removed) field](inflect: true) removed")
                changeLine(count: summary.refreshed, text: "^[\(summary.refreshed) field](inflect: true) renamed or retyped")
                changeLine(count: summary.reordered, text: "^[\(summary.reordered) field](inflect: true) reordered")
            }
            .padding(.top, 12)
            if summary.valuesCleared > 0 {
                Text("^[\(summary.valuesCleared) stored value](inflect: true) no longer fits its field's new type and will be cleared.")
                    .font(Baron.body(12))
                    .foregroundStyle(Baron.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            Button {
                if let result = try? store.propagateTemplates(forCategoryID: category.id) {
                    propagationResultMessage = Self.resultMessage(result)
                }
            } label: {
                Text("Push to ^[\(summary.affectedAssetCount) thing](inflect: true)")
                    .font(Baron.heading(11.5))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Baron.fill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Baron.surface, in: RoundedRectangle(cornerRadius: Baron.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Baron.Radius.card, style: .continuous)
            .strokeBorder(Baron.accent800, lineWidth: 1.5))
    }

    @ViewBuilder
    private func changeLine(count: Int, text: LocalizedStringKey) -> some View {
        if count > 0 {
            HStack(spacing: 8) {
                Circle().fill(Baron.accent500).frame(width: 5, height: 5)
                Text(text)
                    .font(Baron.body(13))
                    .foregroundStyle(Baron.neutral700)
            }
        }
    }

    private static func resultMessage(_ s: TemplatePropagationSummary) -> LocalizedStringKey {
        if s.valuesCleared > 0 {
            return "Updated ^[\(s.affectedAssetCount) thing](inflect: true). Cleared ^[\(s.valuesCleared) value](inflect: true) that no longer fit its field's new type."
        }
        return "Updated ^[\(s.affectedAssetCount) thing](inflect: true)."
    }

    private var deleteButton: some View {
        Button { deleteConfirmationPresented = true } label: {
            Text("Delete category")
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

// MARK: - Name

private struct CategoryNameEditor: View {
    @Environment(AssetStore.self) private var store
    let category: AssetCategory
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(category: AssetCategory) {
        self.category = category
        _text = State(initialValue: category.name)
    }

    var body: some View {
        TextField("Name", text: $text)
            .font(Baron.body(16, .medium))
            .foregroundStyle(Baron.text)
            .focused($isFocused)
            .onSubmit { commit() }
            .commitsPendingEdit(focused: isFocused) { commit() }
            .limitLength(TextLimits.categoryName, text: $text)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .baronCard(radius: 13, elevation: .low)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { text = category.name; return }
        guard trimmed != category.name else { return }
        try? store.updateCategory(id: category.id, name: trimmed)
    }
}

// MARK: - Field row

/// A template field. Collapsed it shows name, type, and a Required pill; expanded it offers
/// inline rename, the Required toggle, and type chips for the five basic types.
///
/// Type chips cover only the basics on purpose. Switching to a pick list or a composite needs a
/// second choice (*which* list, *which* composite) plus a max-length, which is exactly what the
/// existing property sheet already asks — so "Type & default value" opens that rather than
/// growing a second, half-complete copy of it inline.
private struct CategoryFieldRow: View {
    @Environment(AssetStore.self) private var store

    let categoryID: UUID
    let property: AssetProperty
    let isExpanded: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: () -> Void
    let onMove: (Int) -> Void
    let onEditDetails: () -> Void
    let onRemove: () -> Void

    @State private var draftName: String = ""
    @FocusState private var nameFocused: Bool

    private var isBasic: Bool {
        if case .basic = property.definition.type { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onToggle) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BuiltInTypes.localizedSeedName(id: property.definition.id, currentName: property.definition.name))
                            .font(Baron.body(14.5, .medium))
                            .foregroundStyle(Baron.text)
                            .lineLimit(1)
                        Text(property.definition.type.displayName)
                            .font(Baron.body(11.5))
                            .foregroundStyle(Baron.neutral600)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if property.definition.isRequired {
                    Text("Required")
                        .font(Baron.body(9.5, .semibold))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(Baron.accent800)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Baron.accent100, in: Capsule())
                }
                iconButton("chevron.up", enabled: canMoveUp) { onMove(-1) }
                iconButton("chevron.down", enabled: canMoveDown) { onMove(1) }
                iconButton("xmark", tint: Baron.danger) { onRemove() }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)

            if isExpanded {
                VStack(alignment: .leading, spacing: 11) {
                    TextField("Field name", text: $draftName)
                        .font(Baron.body(14, .medium))
                        .foregroundStyle(Baron.text)
                        .focused($nameFocused)
                        .onSubmit { commitName() }
                        .commitsPendingEdit(focused: nameFocused) { commitName() }
                        .limitLength(TextLimits.propertyName, text: $draftName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Baron.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    FlowLayout(spacing: 6) {
                        ForEach(BasicType.userSelectable, id: \.self) { basic in
                            let selected = property.definition.type == .basic(basic)
                            Button { setType(.basic(basic)) } label: {
                                Text(basic.displayName)
                                    .font(Baron.body(11.5, .medium))
                                    .foregroundStyle(selected ? Color.white : Baron.text)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(selected ? Baron.fill : Baron.surface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        if !isBasic {
                            Text(property.definition.type.displayName)
                                .font(Baron.body(11.5, .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Baron.fill, in: Capsule())
                        }
                    }

                    Button {
                        try? store.updateTemplateProperty(id: property.id, inCategoryID: categoryID,
                                                          isRequired: !property.definition.isRequired)
                    } label: {
                        HStack(spacing: 10) {
                            Text("Required on new things")
                                .font(Baron.body(13))
                                .foregroundStyle(Baron.neutral700)
                            Spacer(minLength: 0)
                            ToggleTrack(isOn: property.definition.isRequired)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onEditDetails) {
                        Text("Type & default value")
                            .font(Baron.body(12, .medium))
                            .foregroundStyle(Baron.accent800)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                                .strokeBorder(Baron.neutral300, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 13)
            }
        }
        .baronCard(radius: 15, elevation: .low)
        .onChange(of: isExpanded, initial: true) { _, expanded in
            if expanded { draftName = property.definition.name }
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

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { draftName = property.definition.name; return }
        guard trimmed != property.definition.name else { return }
        try? store.updateTemplateProperty(id: property.id, inCategoryID: categoryID, name: trimmed)
    }

    /// A type change clears the template's default value (see `updateTemplateProperty`), which
    /// is why the chips are a deliberate tap and not a swipe.
    private func setType(_ type: PropertyType) {
        guard type != property.definition.type else { return }
        try? store.updateTemplateProperty(id: property.id, inCategoryID: categoryID, type: type)
    }
}

// MARK: - Toggle

/// The design's pill toggle. A plain `Toggle` would pull in the system tint and control metrics,
/// which read as foreign next to everything else on these screens.
struct ToggleTrack: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Baron.fill : Baron.neutral300)
            .frame(width: 42, height: 25)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 19, height: 19)
                    .padding(3)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
