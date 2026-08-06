import SwiftUI

// MARK: - Belongs-to row

struct BelongsToRow: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    @State private var pickerPresented = false

    private var parent: Asset? {
        guard let id = asset.parentID else { return nil }
        return store.assets[id]
    }

    /// The asset itself and its descendants can't become its own parent.
    private var excludedIDs: Set<UUID> {
        var ids = Set(asset.descendants.map(\.id))
        ids.insert(asset.id)
        return ids
    }

    var body: some View {
        LabeledContent("Belongs to") {
            if let parent {
                HStack(spacing: 12) {
                    Text(parent.name)
                        .foregroundStyle(.primary)
                    Button("Change") { pickerPresented = true }
                }
            } else {
                Button("Select…") { pickerPresented = true }
            }
        }
        .sheet(isPresented: $pickerPresented) {
            AssetParentPickerSheet(excludedIDs: excludedIDs, selectedID: asset.parentID) { selectedID in
                if let newID = selectedID {
                    try? store.moveAsset(assetID: asset.id, toParentID: newID)
                } else {
                    try? store.removeFromParent(assetID: asset.id)
                }
                pickerPresented = false
            }
        }
    }
}

/// Label-above-value "Belongs to" row that edits only a local selection — used by the
/// asset creation form, where no `Asset` exists yet to move in the store.
struct AssetParentSelectionRow: View {
    @Environment(AssetStore.self) private var store
    @Binding var parentID: UUID?
    @State private var pickerPresented = false

    private var parentName: String? {
        parentID.flatMap { store.assets[$0] }?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PropertyLabel(name: "Belongs to", onEditLabel: nil)
            Button { pickerPresented = true } label: {
                HStack {
                    Text(parentName ?? "None (top level)")
                        .foregroundStyle(parentName == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $pickerPresented) {
            AssetParentPickerSheet(selectedID: parentID) { selected in
                parentID = selected
                pickerPresented = false
            }
        }
    }
}

struct AssetParentPickerSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The asset itself and its descendants — empty when picking a parent for an
    /// asset that doesn't exist yet, since it can have no descendants.
    var excludedIDs: Set<UUID> = []
    /// Currently chosen parent, shown with a checkmark.
    var selectedID: UUID? = nil
    let onSelect: (UUID?) -> Void

    private var candidates: [Asset] {
        store.allAssets
            .filter { !excludedIDs.contains($0.id) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                    } label: {
                        Label("None (top level)", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                if !candidates.isEmpty {
                    Section("Assets") {
                        ForEach(candidates) { candidate in
                            Button {
                                onSelect(candidate.id)
                            } label: {
                                HStack {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(candidate.name)
                                                .foregroundStyle(.primary)
                                            Text(candidate.category.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: candidate.category.iconName)
                                            .foregroundStyle(.tint)
                                    }
                                    Spacer()
                                    if candidate.id == selectedID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Belongs To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
