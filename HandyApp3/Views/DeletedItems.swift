import SwiftUI

/// The three bins behind Setup → Deleted items. They were stock `List`s with swipe actions and
/// a "Swipe on any row for actions" footer sitting inside an otherwise Baron screen — the exact
/// hidden-action problem the redesign has been undoing everywhere else. Each row now carries
/// its actions as buttons, and the reason a row can't be purged (an edit after the delete
/// decision, or a category still in use) is stated on the row rather than inferred from a
/// missing swipe.

// MARK: - Shared row chrome

/// One deleted record: title, why it's still here, and its actions.
private struct DeletedRow<Actions: View>: View {
    let title: String
    var iconName: String?
    let subtitle: LocalizedStringKey
    /// Shown when the record is held back from auto-purge — see `isProtectedFromAutoPurge`.
    var protected: Bool = false
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Baron.accent800)
                        .frame(width: 34, height: 34)
                        .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Baron.body(15, .medium))
                        .foregroundStyle(Baron.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Baron.body(11.5))
                        .foregroundStyle(Baron.neutral600)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if protected {
                Text("Edited after it was deleted, so it won't be removed on its own.")
                    .font(Baron.body(11.5))
                    .foregroundStyle(Baron.accent800)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            HStack(spacing: 7) { actions }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .baronCard(radius: 15, elevation: .low)
    }
}

private struct DeletedAction: View {
    let title: LocalizedStringKey
    var tint: Color = Baron.accent800
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Baron.body(12, .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Baron.surface, in: RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous)
                    .strokeBorder(Baron.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct DeletedEmptyState: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(Baron.body(13))
            .foregroundStyle(Baron.neutral600)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 20)
            .baronCard(radius: 16, elevation: .low)
    }
}

/// Days left before the purge sweep takes a record, as the rows word it.
private func purgeSubtitle(deletedAt: Date?) -> LocalizedStringKey {
    let elapsed = Calendar.current.dateComponents([.day], from: deletedAt ?? Date(), to: Date()).day ?? 0
    let remaining = max(0, AppPreference.DaysToRetainDeletedItems - elapsed)
    return "Removed for good in ^[\(remaining) day](inflect: true)"
}

// MARK: - Things

struct DeletedAssetsView: View {
    @Environment(AssetStore.self) private var store
    @State private var paywallPresented = false

    // Only the roots of deleted families — descendants stay linked internally and are excluded.
    private var sorted: [Asset] {
        store.deletedAssets
            .filter { $0.isRoot }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if sorted.isEmpty {
                    DeletedEmptyState(text: "Nothing deleted. Things you delete wait here before they're removed for good.")
                } else {
                    ForEach(sorted) { asset in
                        row(asset)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .sheet(isPresented: $paywallPresented) { PaywallView() }
    }

    private func row(_ asset: Asset) -> some View {
        let inside = asset.descendants.count
        return DeletedRow(
            title: asset.name,
            iconName: asset.category.iconName,
            subtitle: subtitle(asset, inside: inside),
            protected: asset.isProtectedFromAutoPurge
        ) {
            DeletedAction(title: "Restore") {
                // The subtree comes back together, so the free tier has to have room for all
                // of it — not just the root.
                guard store.hasCapacity(forAdditional: 1 + inside) else {
                    paywallPresented = true
                    return
                }
                try? store.restoreAsset(id: asset.id)
            }
            DeletedAction(title: "Delete now", tint: Baron.danger) {
                try? store.hardDeleteAsset(id: asset.id)
            }
        }
    }

    private func subtitle(_ asset: Asset, inside: Int) -> LocalizedStringKey {
        if inside > 0 {
            return "^[\(inside) thing](inflect: true) inside · deleted with it"
        }
        // A protected asset won't age out on its own — a countdown would imply an eventual
        // auto-purge that the gate is specifically refusing to do.
        guard !asset.isProtectedFromAutoPurge else { return "Kept until you restore or delete it" }
        return purgeSubtitle(deletedAt: asset.deletedAt)
    }
}

// MARK: - Categories

struct DeletedCategoriesView: View {
    @Environment(AssetStore.self) private var store

    private var sorted: [AssetCategory] {
        store.deletedCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if sorted.isEmpty {
                    DeletedEmptyState(text: "No deleted categories.")
                } else {
                    ForEach(sorted) { category in
                        row(category)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
    }

    private func row(_ category: AssetCategory) -> some View {
        let count = store.associatedAssetCount(categoryID: category.id)
        return DeletedRow(
            title: category.name,
            iconName: category.iconName,
            subtitle: subtitle(category, count: count),
            protected: count == 0 && category.isProtectedFromAutoPurge
        ) {
            DeletedAction(title: "Restore") {
                try? store.restoreCategory(id: category.id)
            }
            // A category still filed against by things has no hard delete — those things would
            // lose the category they point at.
            if count == 0 {
                DeletedAction(title: "Delete now", tint: Baron.danger) {
                    try? store.hardDeleteCategory(id: category.id)
                }
            }
        }
    }

    private func subtitle(_ category: AssetCategory, count: Int) -> LocalizedStringKey {
        if count > 0 {
            return "Still used by ^[\(count) thing](inflect: true), so it's kept"
        }
        guard !category.isProtectedFromAutoPurge else { return "Kept until you restore or delete it" }
        return purgeSubtitle(deletedAt: category.deletedAt)
    }
}

// MARK: - Pick lists

struct DeletedComboListsView: View {
    @Environment(AssetStore.self) private var store

    private var sorted: [ComboListDefinition] {
        store.deletedComboListDefinitions.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if sorted.isEmpty {
                    DeletedEmptyState(text: "No deleted pick lists.")
                } else {
                    ForEach(sorted) { list in
                        // No "Delete now": a pick list has no sync-safe hard-delete path (unlike
                        // things and categories) — removing it outright resurrects on the next
                        // sync and silently drops any field still typed on it. Restore only.
                        DeletedRow(
                            title: list.name,
                            subtitle: "Kept until you restore it · ^[\(list.allOptions.count) value](inflect: true)"
                        ) {
                            DeletedAction(title: "Restore") {
                                try? store.restoreComboList(id: list.id)
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
    }
}
