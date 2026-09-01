import SwiftUI

// MARK: - Belongs-to rows

/// "Belongs to" on the Thing detail screen, editing the live asset through the store.
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
        ParentField(parentName: parent?.name) { pickerPresented = true }
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

/// "Belongs to" on the create form, editing only a local selection — no `Asset` exists yet to
/// move in the store.
struct AssetParentSelectionRow: View {
    @Environment(AssetStore.self) private var store
    @Binding var parentID: UUID?
    @State private var pickerPresented = false

    private var parentName: String? {
        parentID.flatMap { store.assets[$0] }?.name
    }

    var body: some View {
        ParentField(parentName: parentName) { pickerPresented = true }
            .sheet(isPresented: $pickerPresented) {
                AssetParentPickerSheet(selectedID: parentID) { selected in
                    parentID = selected
                    pickerPresented = false
                }
            }
    }
}

/// The shared button both rows present. Previously these were a `LabeledContent` and a
/// label-above-value pair — two shapes for one control, and neither belonged on a Baron screen.
private struct ParentField: View {
    let parentName: String?
    let onTap: () -> Void

    var body: some View {
        RecordField(label: "Belongs to") {
            Button(action: onTap) {
                HStack(spacing: 9) {
                    Text(parentName ?? String(localized: "None · top level", locale: .appPreferred))
                        .font(Baron.body(15, .medium))
                        .foregroundStyle(parentName == nil ? Baron.neutral500 : Baron.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: "›")
                        .font(Baron.body(13, .medium))
                        .foregroundStyle(Baron.neutral400)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .baronCard(radius: Baron.Radius.field, elevation: .low)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Picker sheet

struct AssetParentPickerSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The asset itself and its descendants — empty when picking a parent for an
    /// asset that doesn't exist yet, since it can have no descendants.
    var excludedIDs: Set<UUID> = []
    /// Currently chosen parent, shown with a checkmark.
    var selectedID: UUID? = nil
    let onSelect: (UUID?) -> Void

    @State private var query = ""

    private var candidates: [Asset] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.allAssets
            .filter { asset in
                guard !excludedIDs.contains(asset.id) else { return false }
                guard !trimmed.isEmpty else { return true }
                return asset.name.lowercased().contains(trimmed)
                    || asset.category.name.lowercased().contains(trimmed)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            Baron.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 9) {
                        // Searching is only worth the row once there are enough things that
                        // scanning the list stops being instant.
                        if store.allAssets.count > 8 {
                            searchField.padding(.bottom, 3)
                        }
                        topLevelRow
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
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
            Text("Belongs to")
                .font(Baron.heading(15))
                .foregroundStyle(Baron.text)
            Spacer(minLength: 0)
            Color.clear.frame(width: 62, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Baron.surface)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(Baron.neutral500)
            TextField("Search things", text: $query)
                .font(Baron.body(14))
                .foregroundStyle(Baron.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .baronCard(radius: 15, elevation: .low)
    }

    private var topLevelRow: some View {
        Button { onSelect(nil) } label: {
            HStack(spacing: 10) {
                Text("None · top level")
                    .font(Baron.body(14.5, .medium))
                    .foregroundStyle(Baron.neutral700)
                Spacer(minLength: 0)
                if selectedID == nil {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Baron.accent800)
                }
            }
            .padding(14)
            .baronCard(radius: 16, elevation: .low)
        }
        .buttonStyle(.plain)
    }

    private func candidateRow(_ candidate: Asset) -> some View {
        Button { onSelect(candidate.id) } label: {
            HStack(spacing: 11) {
                Image(systemName: candidate.category.iconName)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Baron.accent800)
                    .frame(width: 34, height: 34)
                    .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(Baron.body(14.5, .medium))
                        .foregroundStyle(Baron.text)
                        .lineLimit(1)
                    Text(BuiltInTypes.localizedSeedName(id: candidate.category.id, currentName: candidate.category.name))
                        .font(Baron.body(11.5))
                        .foregroundStyle(Baron.neutral600)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if candidate.id == selectedID {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Baron.accent800)
                }
            }
            .padding(14)
            .baronCard(radius: 16, elevation: .low)
        }
        .buttonStyle(.plain)
    }
}
