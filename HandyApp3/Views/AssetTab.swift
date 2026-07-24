import SwiftUI

enum AssetListMode: String, CaseIterable {
    case all, tree
    var label: LocalizedStringKey { self == .all ? "All" : "Tree" }
}

struct AssetTab: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var newAssetPresented = false
    @State private var paywallPresented = false
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

    /// Flat asset order matching what the current view mode renders, used to page
    /// between assets via swipe on the detail screen. "All" mirrors the grouped,
    /// name-sorted sections; "Tree" pages only through top-level (parentless) assets,
    /// so drilling into a child leaves the detail screen unpageable.
    private var orderedAssetIDs: [UUID] {
        switch viewMode {
        case .all:
            return groupedAssets.flatMap { $0.assets.map(\.id) }
        case .tree:
            return rootAssets.map(\.id)
        }
    }

    /// Distinct categories offered as jump anchors, name-sorted: every category
    /// holding an asset in "All" view, only top-level assets' categories in "Tree".
    private var anchorCategories: [AssetCategory] {
        switch viewMode {
        case .all:
            return groupedAssets.map(\.category)
        case .tree:
            var seen = Set<UUID>()
            return rootAssets.map(\.category)
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    AppBackground()
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
                                case .all: allList(proxy)
                                case .tree: treeList
                                }
                            }
                        }
                    }
                    .environment(\.colorScheme, .light)
                }
                .navigationTitle("Assets")
                .toolbarColorScheme(.light, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if store.hasAssetCapacity { newAssetPresented = true } else { paywallPresented = true }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    if !anchorCategories.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            jumpMenu(proxy)
                        }
                    }
                }
            }
            .sheet(isPresented: $newAssetPresented) {
                NewAssetSheet()
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallView()
            }
            .onAppear { if router.focusedCategoryID != nil { viewMode = .all } }
            .onChange(of: router.focusedCategoryID) { _, id in
                if id != nil { viewMode = .all }
            }
            .onChange(of: router.pendingNewAsset) { _, pending in
                guard pending else { return }
                router.pendingNewAsset = false
                if store.hasAssetCapacity { newAssetPresented = true } else { paywallPresented = true }
            }
            .navigationDestination(item: $router.pendingAssetID) { id in
                if let asset = store.assets[id], !asset.isDeleted {
                    AssetDetailView(asset: asset, orderedIDs: orderedAssetIDs)
                } else {
                    ContentUnavailableView(
                        "Asset Not Found",
                        systemImage: "shippingbox",
                        description: Text("This asset no longer exists.")
                    )
                }
            }
        }
    }

    private func jumpMenu(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(anchorCategories, id: \.id) { category in
                Button(category.name) {
                    withAnimation {
                        switch viewMode {
                        case .all:
                            proxy.scrollTo(category.id, anchor: .top)
                        case .tree:
                            if let target = rootAssets.first(where: { $0.category.id == category.id }) {
                                proxy.scrollTo(target.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
    }

    private func allList(_ proxy: ScrollViewProxy) -> some View {
        List {
            ForEach(groupedAssets, id: \.category.id) { group in
                Section(header: categoryHeader(group.category)) {
                    ForEach(group.assets) { asset in
                        NavigationLink(destination: AssetDetailView(asset: asset, orderedIDs: orderedAssetIDs)) {
                            AssetRow(asset: asset)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.5))
                .id(group.category.id)
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            guard let id = router.focusedCategoryID else { return }
            DispatchQueue.main.async { flashFocus(id, proxy: proxy) }
        }
        .onChange(of: router.focusedCategoryID) { _, id in
            guard let id else { return }
            flashFocus(id, proxy: proxy)
        }
    }

    /// Scrolls the focused category into view, then clears the highlight after a
    /// brief pause so it reads as a confirmation flash rather than a sticky selection.
    /// Bails on clearing if a newer focus has replaced this one mid-wait.
    private func flashFocus(_ id: UUID, proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(id, anchor: .top) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard router.focusedCategoryID == id else { return }
            withAnimation { router.focusedCategoryID = nil }
        }
    }

    @ViewBuilder
    private func categoryHeader(_ category: AssetCategory) -> some View {
        let focused = router.focusedCategoryID == category.id
        Label(category.name, systemImage: category.iconName)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(focused ? Color.accentColor.opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.2), value: focused)
    }

    private var treeList: some View {
        List {
            ForEach(rootAssets) { asset in
                AssetTreeRow(asset: asset, depth: 0, expanded: $expanded, orderedIDs: orderedAssetIDs)
                    .id(asset.id)
                    .listRowBackground(Color.white.opacity(0.5))
            }
        }
        .scrollContentBackground(.hidden)
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
    let orderedIDs: [UUID]
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
                AssetDetailView(asset: asset, orderedIDs: orderedIDs)
            }

            if isExpanded {
                ForEach(children) { child in
                    AssetTreeRow(asset: child, depth: depth + 1, expanded: $expanded, orderedIDs: orderedIDs)
                }
            }
        }
    }
}
