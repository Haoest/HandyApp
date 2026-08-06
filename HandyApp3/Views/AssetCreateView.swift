import SwiftUI

/// Minimal new-asset form: category (read-only), name, and an optional parent.
/// Holds the draft locally and creates nothing in the store until Save, so an
/// abandoned form (Cancel, or swiping the sheet away) leaves no asset behind and no
/// stray "asset created" entry in the activity log. Base properties are filled in
/// afterwards on the asset detail screen.
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
    /// Called when the user cancels. The presenter is responsible for dismissing.
    let onCancel: () -> Void

    @State private var name = ""
    @State private var parentID: UUID?
    @State private var didPrefill = false
    @State private var paywallPresented = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    PropertyLabel(name: "Category", onEditLabel: nil)
                    Label(category.name, systemImage: category.iconName)
                }
                VStack(alignment: .leading, spacing: 4) {
                    PropertyLabel(name: "Name", onEditLabel: nil)
                    HStack {
                        TextField("Asset name", text: $name)
                        if !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                AssetParentSelectionRow(parentID: $parentID)
            }
        }
        .navigationTitle("New \(category.name)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear { prefillDraft() }
        .sheet(isPresented: $paywallPresented) {
            PaywallView(reason: .assets)
        }
        .alert("Could Not Create Asset", isPresented: Binding(
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
    /// "<Category> <n+1>", unless a name was supplied.
    private func prefillDraft() {
        guard !didPrefill else { return }
        didPrefill = true
        parentID = initialParentID
        if let provided = initialName, !provided.trimmingCharacters(in: .whitespaces).isEmpty {
            name = provided
        } else {
            let count = (try? store.assets(ofCategoryID: category.id))?.count ?? 0
            name = "\(category.name) \(count + 1)"
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        do {
            let asset = try store.createAsset(name: trimmedName, categoryID: category.id)
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

// MARK: - New asset sheet (category picker)

struct NewAssetSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initialName: String? = nil
    /// Parent to pre-select on the create form (see `AssetCreateView.initialParentID`).
    var initialParentID: UUID? = nil
    let onCreated: (Asset) -> Void

    @State private var selectedCategoryID: UUID?

    var body: some View {
        NavigationStack {
            CategoryPickerContent { category in selectedCategoryID = category.id }
                .navigationTitle("New Asset")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(item: $selectedCategoryID) { id in
                    if let category = store.categories[id] {
                        AssetCreateView(
                            category: category,
                            initialName: initialName,
                            initialParentID: initialParentID,
                            onCreated: { asset in onCreated(asset) },
                            onCancel: { dismiss() }
                        )
                    }
                }
        }
    }
}

private struct CategoryPickerContent: View {
    @Environment(AssetStore.self) private var store
    let onSelect: (AssetCategory) -> Void

    private var sortedCategories: [AssetCategory] {
        store.allCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if store.allCategories.isEmpty {
            ContentUnavailableView(
                "No Categories",
                systemImage: "folder",
                description: Text("Create a category first in the Categories tab.")
            )
        } else {
            List {
                Section("Select Category") {
                    ForEach(sortedCategories) { category in
                        Button(category.name) {
                            onSelect(category)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}
