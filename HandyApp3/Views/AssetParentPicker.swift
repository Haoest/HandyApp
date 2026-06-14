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
            AssetParentPickerSheet(asset: asset) { selectedID in
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

struct AssetParentPickerSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    let onSelect: (UUID?) -> Void

    private var excludedIDs: Set<UUID> {
        var ids = Set(asset.descendants.map(\.id))
        ids.insert(asset.id)
        return ids
    }

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
                                    if candidate.id == asset.parentID {
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
