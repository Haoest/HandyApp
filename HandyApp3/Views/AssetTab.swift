import SwiftUI

enum AssetListMode: String, CaseIterable {
    case all, tree
    var label: String { self == .all ? "All" : "Tree" }
}

struct AssetTab: View {
    @Environment(AssetStore.self) private var store
    @State private var newAssetPresented = false
    @State private var viewMode: AssetListMode = .all
    @State private var expanded: Set<UUID> = []

    private var groupedAssets: [(category: AssetCategory, assets: [Asset])] {
        let grouped = Dictionary(grouping: store.allAssets) { $0.category.id }
        return grouped
            .compactMap { catID, assets -> (AssetCategory, [Asset])? in
                guard let cat = store.categories[catID] else { return nil }
                return (cat, assets.sorted { $0.name.localizedCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.0.name.localizedCompare($1.0.name) == .orderedAscending }
    }

    private var rootAssets: [Asset] {
        store.rootAssets
            .filter { !$0.isDeleted }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !store.allAssets.isEmpty {
                    Picker("View", selection: $viewMode) {
                        ForEach(AssetListMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                Group {
                    if store.allAssets.isEmpty {
                        ContentUnavailableView(
                            "No Assets",
                            systemImage: "shippingbox",
                            description: Text("Tap + to add your first asset.")
                        )
                    } else {
                        switch viewMode {
                        case .all: allList
                        case .tree: treeList
                        }
                    }
                }
            }
            .navigationTitle("Assets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newAssetPresented = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $newAssetPresented) {
                NewAssetSheet()
            }
        }
    }

    private var allList: some View {
        List {
            ForEach(groupedAssets, id: \.category.id) { group in
                Section(header: Label(group.category.name, systemImage: group.category.iconName)) {
                    ForEach(group.assets) { asset in
                        NavigationLink(destination: AssetDetailView(asset: asset)) {
                            AssetRow(asset: asset)
                        }
                    }
                }
            }
        }
    }

    private var treeList: some View {
        List {
            ForEach(rootAssets) { asset in
                AssetTreeRow(asset: asset, depth: 0, expanded: $expanded)
            }
        }
    }
}

private struct AssetRow: View {
    let asset: Asset

    var body: some View {
        HStack {
            Text(asset.name)
            Spacer()
            Text(asset.modifiedDate, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct AssetTreeRow: View {
    let asset: Asset
    let depth: Int
    @Binding var expanded: Set<UUID>
    @State private var showDetail = false

    private var children: [Asset] {
        asset.children
            .filter { !$0.isDeleted }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    private var hasChildren: Bool { !children.isEmpty }
    private var isExpanded: Bool { expanded.contains(asset.id) }

    var body: some View {
        Group {
            HStack(spacing: 8) {
                Button {
                    guard hasChildren else { return }
                    if isExpanded { expanded.remove(asset.id) } else { expanded.insert(asset.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(hasChildren ? 1 : 0)
                        Image(systemName: asset.category.iconName)
                            .foregroundStyle(.tint)
                        Text(asset.name)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showDetail = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16 + CGFloat(depth) * 20, bottom: 6, trailing: 16))
            .navigationDestination(isPresented: $showDetail) {
                AssetDetailView(asset: asset)
            }

            if isExpanded {
                ForEach(children) { child in
                    AssetTreeRow(asset: child, depth: depth + 1, expanded: $expanded)
                }
            }
        }
    }
}
