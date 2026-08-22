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
    @State private var pendingAssetName: String? = nil
    @State private var createdAssetID: UUID? = nil
    @State private var viewMode: AssetListMode = .all
    @State private var expanded: Set<UUID> = []

    /// Assets bucketed into name-sorted category sections. Categories resolve from the raw
    /// `store.categories` dict, not `allCategories`, so an asset under a soft-deleted category
    /// still gets a section instead of vanishing from the list.
    private func grouped(_ assets: [Asset]) -> [(category: AssetCategory, assets: [Asset])] {
        let grouped = Dictionary(grouping: assets) { $0.category.id }
        return grouped
            .compactMap { catID, assets -> (AssetCategory, [Asset])? in
                guard let cat = store.categories[catID] else { return nil }
                return (cat, assets.sorted { $0.name.localizedCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.0.name.localizedCompare($1.0.name) == .orderedAscending }
    }

    private var groupedAssets: [(category: AssetCategory, assets: [Asset])] { grouped(store.allAssets) }

    private var rootAssets: [Asset] {
        store.rootAssets
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var groupedRootAssets: [(category: AssetCategory, assets: [Asset])] { grouped(rootAssets) }

    /// Flat asset order matching what the current view mode renders, used to page
    /// between assets via swipe on the detail screen. "All" mirrors the grouped,
    /// name-sorted sections; "Tree" pages only through top-level (parentless) assets, in the
    /// same category-section order shown on screen, so drilling into a child leaves the
    /// detail screen unpageable.
    private var orderedAssetIDs: [UUID] {
        switch viewMode {
        case .all:
            return groupedAssets.flatMap { $0.assets.map(\.id) }
        case .tree:
            return groupedRootAssets.flatMap { $0.assets.map(\.id) }
        }
    }

    /// Distinct categories offered as jump anchors, name-sorted: every category holding an
    /// asset in "All" view, every category holding a top-level asset in "Tree".
    private var anchorCategories: [AssetCategory] {
        switch viewMode {
        case .all:
            return groupedAssets.map(\.category)
        case .tree:
            return groupedRootAssets.map(\.category)
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
                                case .all: allList
                                case .tree: treeList
                                }
                            }
                        }
                        .onAppear {
                            guard let id = router.focusedCategoryID else { return }
                            DispatchQueue.main.async { flashFocus(id, proxy: proxy) }
                        }
                        .onChange(of: router.focusedCategoryID) { _, id in
                            guard let id else { return }
                            flashFocus(id, proxy: proxy)
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
            .sheet(isPresented: $newAssetPresented, onDismiss: {
                pendingAssetName = nil
                // Push after the sheet has finished dismissing — pushing onto the
                // NavigationStack while the sheet is still animating away can be
                // dropped by SwiftUI.
                if let id = createdAssetID {
                    createdAssetID = nil
                    router.pendingAssetID = id
                }
            }) {
                NewAssetSheet(initialName: pendingAssetName) { asset in
                    createdAssetID = asset.id
                    newAssetPresented = false
                }
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallView()
            }
            .onAppear {
                if router.pendingNewAsset {
                    router.pendingNewAsset = false
                    pendingAssetName = router.pendingNewAssetName
                    router.pendingNewAssetName = nil
                    if store.hasAssetCapacity { newAssetPresented = true } else { paywallPresented = true }
                }
            }
            .onChange(of: router.pendingNewAsset) { _, pending in
                guard pending else { return }
                router.pendingNewAsset = false
                pendingAssetName = router.pendingNewAssetName
                router.pendingNewAssetName = nil
                if store.hasAssetCapacity { newAssetPresented = true } else { paywallPresented = true }
            }
            .navigationDestination(item: $router.pendingAssetID) { id in
                if let asset = store.assets[id], !asset.isDeleted, !asset.isPurged {
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
                    withAnimation { proxy.scrollTo(category.id, anchor: .top) }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
    }

    private var allList: some View {
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
        Label {
            Text(category.name)
        } icon: {
            Image(systemName: category.iconName)
                .foregroundStyle(.tint)
        }
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
            ForEach(groupedRootAssets, id: \.category.id) { group in
                Section(header: categoryHeader(group.category)) {
                    ForEach(group.assets) { asset in
                        AssetTreeRow(asset: asset, depth: 0, expanded: $expanded, orderedIDs: orderedAssetIDs)
                    }
                }
                .listRowBackground(Color.white.opacity(0.5))
                .id(group.category.id)
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
            .filter { !$0.isDeleted && !$0.isPurged }
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
                        if hasChildren {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            .padding(.leading, CGFloat(depth) * 30)
            .padding(.vertical, 2)
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
