import SwiftUI

/// Minimal new-asset form: category (read-only), name, and an optional parent. Base
/// properties are otherwise filled in afterwards on the asset detail screen — the one
/// exception is a category's required "Type" combo-list field (e.g. Appliance's), surfaced
/// here because picking it drives the Name auto-fill below.
/// Holds the draft locally and creates nothing in the store until Save, so an
/// abandoned form (Cancel, or swiping the sheet away) leaves no asset behind and no
/// stray "asset created" entry in the activity log.
struct AssetCreateView: View {
    @Environment(AssetStore.self) private var store

    let category: AssetCategory
    /// Name override (e.g. from the Siri "add a named asset" intent); otherwise a
    /// default name is derived from the category.
    var initialName: String? = nil
    /// Pre-selected parent, e.g. when creating an asset inside an existing one.
    /// Only a starting value — the user can still change it before saving.
    var initialParentID: UUID? = nil
    /// Called with the freshly created asset once Save commits it to the store.
    /// The presenter is responsible for dismissing and navigating to it.
    let onCreated: (Asset) -> Void
    /// Called by the leading "Back" button. `NewAssetSheet` uses it to return to the category
    /// step; the sheet's own swipe-down is what abandons the whole flow.
    let onCancel: () -> Void

    @State private var name = ""
    @State private var parentID: UUID?
    @State private var didPrefill = false
    @State private var paywallPresented = false
    @State private var errorMessage: String?

    /// The category's required "Type" combo-list field, if it has one (currently just
    /// Appliance). Surfaced directly on this otherwise property-free create form because
    /// picking it drives the Name auto-fill below.
    @State private var typeValue: StoredValue?
    /// The last name this view generated on the user's behalf — from `prefillDraft`'s default,
    /// or from a prior Type selection. As long as `name` still equals this, the user hasn't
    /// typed anything of their own, so a new Type selection is free to overwrite it again.
    @State private var autoFilledName: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var typeDefinition: PropertyDefinition? {
        category.propertyTemplates.first {
            !$0.isDeleted && $0.definition.name == "Type" && isComboList($0.definition.type)
        }?.definition
    }

    private func isComboList(_ type: PropertyType) -> Bool {
        if case .comboList = type { return true }
        return false
    }

    private var isTypeMissing: Bool {
        guard let typeDefinition, typeDefinition.isRequired else { return false }
        return typeValue == nil
    }

    private var typeList: ComboListDefinition? {
        guard let typeDefinition, case .comboList(let list) = typeDefinition.type else { return nil }
        return list
    }

    /// Options for the required "Type" field, when the category has one.
    private var typeOptions: [String] {
        guard let typeDefinition, case .comboList(let list) = typeDefinition.type else { return [] }
        guard let maxLength = typeDefinition.maxLength else { return list.allOptions }
        return list.allOptions.filter { $0.count <= maxLength }
    }

    private var selectedType: String? {
        if case .text(let value) = typeValue { return value }
        return nil
    }

    private var fieldCount: Int { category.liveTemplates.count }

    var body: some View {
        RecordSheetScaffold(
            title: "New thing",
            saveLabel: "Create",
            canSave: !trimmedName.isEmpty && !isTypeMissing,
            onSave: save,
            onCancel: onCancel,
            dismissesOnSave: false,
            cancelLabel: "Back"
        ) {
            Text("Step 2 of 2 — \(category.name)")
                .font(Baron.body(12.5))
                .foregroundStyle(Baron.neutral600)

            if let typeList, let typeDefinition {
                RecordField(label: isTypeMissing ? "Type · required" : "Type") {
                    VStack(alignment: .leading, spacing: 10) {
                        if !typeOptions.isEmpty {
                            RecordChipPicker(options: typeOptions, selection: selectedType ?? "",
                                             title: { $0 }) { option in
                                typeValue = .text(option)
                            }
                        }
                        // An extensible list accepts anything typed and adopts it as a new
                        // option on save; a closed one would have the store reject it, so the
                        // field is only offered where it can actually succeed.
                        if typeList.isUserExtensible {
                            ComboListField(label: nil, list: typeList, current: selectedType ?? "",
                                           maxLength: typeDefinition.maxLength,
                                           showsSuggestions: false,
                                           prompt: "Something else") { newValue in
                                typeValue = newValue.map(StoredValue.text)
                            }
                            .font(Baron.body(14, .medium))
                            .foregroundStyle(Baron.text)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .baronCard(radius: Baron.Radius.field, elevation: .low)
                            Text("Not on the list? Type it in — it'll be added to \(typeList.name).")
                                .font(Baron.body(11.5))
                                .foregroundStyle(Baron.neutral600)
                        }
                    }
                }
            }

            RecordField(label: "Name") {
                HStack(spacing: 9) {
                    TextField("What do you call it?", text: $name)
                        .font(Baron.body(15, .medium))
                        .foregroundStyle(Baron.text)
                        .limitLength(TextLimits.assetName, text: $name)
                    if !name.isEmpty {
                        Button { name = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Baron.neutral400)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .baronCard(radius: Baron.Radius.field, elevation: .low)
            }

            AssetParentSelectionRow(parentID: $parentID)

            if fieldCount > 0 {
                RecordNote(text: String(localized: "^[\(fieldCount) field](inflect: true) from \(category.name) will be copied in, ready to fill."))
            }
        }
        .onChange(of: typeValue) { _, newValue in applyTypeSelection(newValue) }
        .onAppear { prefillDraft() }
        .sheet(isPresented: $paywallPresented) {
            PaywallView(reason: .assets)
        }
        .alert("Could not create", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Seeds the draft once, so retyping the name (or re-picking a parent) isn't
    /// clobbered on re-appear. Default name mirrors the previous behavior:
    /// "<Category> <n+1>", unless a name was supplied. A supplied name is treated as
    /// intentional, not an autofill placeholder, so a later Type pick won't overwrite it.
    private func prefillDraft() {
        guard !didPrefill else { return }
        didPrefill = true
        parentID = initialParentID
        if let provided = initialName, !provided.trimmingCharacters(in: .whitespaces).isEmpty {
            name = provided
        } else {
            let count = (try? store.assets(ofCategoryID: category.id))?.count ?? 0
            name = "\(category.name) \(count + 1)"
            autoFilledName = name
        }
    }

    /// Regenerates Name from the picked Type option — "<option> (<n+1>)" — but only while
    /// `name` still matches the last value this view set on its own. Once the user types
    /// something else, `name` and `autoFilledName` diverge and further Type picks stop
    /// touching Name.
    private func applyTypeSelection(_ newValue: StoredValue?) {
        guard case .text(let optionName) = newValue, !optionName.isEmpty else { return }
        guard name == (autoFilledName ?? "") else { return }
        let count = (try? store.assets(ofCategoryID: category.id))?.count ?? 0
        let generated = "\(optionName) (\(count + 1))"
        name = generated
        autoFilledName = generated
    }

    private func save() {
        guard !trimmedName.isEmpty, !isTypeMissing else { return }
        do {
            let asset = try store.createAsset(name: trimmedName, categoryID: category.id)
            if let typeDefinition, let typeValue {
                try? store.setPropertyValue(typeValue, forDefinitionID: typeDefinition.id, onAssetID: asset.id)
            }
            // A brand-new asset has no parent yet, so addChild (not moveAsset) applies.
            if let parentID { try? store.addChild(assetID: asset.id, toParentID: parentID) }
            onCreated(asset)
        } catch AssetStoreError.freeLimitReached {
            // Capacity is pre-checked before this form opens, but it can change while
            // the form is still up (e.g. another asset created elsewhere).
            paywallPresented = true
        } catch {
            errorMessage = "\(error)"
        }
    }
}

// MARK: - New thing sheet (step 1: category)

struct NewAssetSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initialName: String? = nil
    /// Parent to pre-select on the create form (see `AssetCreateView.initialParentID`).
    var initialParentID: UUID? = nil
    let onCreated: (Asset) -> Void

    @State private var selectedCategoryID: UUID?

    private var sortedCategories: [AssetCategory] {
        store.allCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Baron.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if store.allCategories.isEmpty {
                        emptyState
                    } else {
                        picker
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedCategoryID) { id in
                if let category = store.categories[id], !category.isDeleted {
                    AssetCreateView(
                        category: category,
                        initialName: initialName,
                        initialParentID: initialParentID,
                        onCreated: { asset in onCreated(asset) },
                        onCancel: { selectedCategoryID = nil }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Text("Cancel")
                    .font(Baron.body(12.5, .medium))
                    .foregroundStyle(Baron.neutral700)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Baron.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text("New thing")
                .font(Baron.heading(15))
                .foregroundStyle(Baron.text)
            Spacer(minLength: 0)
            // Balances the Cancel button so the title stays centred.
            Color.clear.frame(width: 62, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Baron.surface)
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Step 1 of 2 — pick a category template")
                    .font(Baron.body(12.5))
                    .foregroundStyle(Baron.neutral600)
                ForEach(sortedCategories) { category in
                    Button { selectedCategoryID = category.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(Baron.accent800)
                                .frame(width: 38, height: 38)
                                .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.name)
                                    .font(Baron.heading(16))
                                    .foregroundStyle(Baron.text)
                                    .lineLimit(1)
                                Text("^[\(category.liveTemplates.count) field](inflect: true) copied in")
                                    .font(Baron.body(12))
                                    .foregroundStyle(Baron.neutral600)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("›")
                                .font(Baron.body(13, .medium))
                                .foregroundStyle(Baron.neutral400)
                        }
                        .padding(14)
                        .baronCard(elevation: .low)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No categories yet")
                .font(Baron.heading(18))
                .foregroundStyle(Baron.text)
            Text("A thing needs a category to copy its fields from. Create one under Setup → Categories.")
                .font(Baron.body(13))
                .foregroundStyle(Baron.neutral600)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
