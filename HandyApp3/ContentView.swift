import SwiftUI

// MARK: - Root

struct ContentView: View {
    var body: some View {
        TabView {
            HomeTab()
                .tabItem { Image(systemName: "house") }
            AssetTab()
                .tabItem { Image(systemName: "shippingbox") }
            CategoryTab()
                .tabItem { Image(systemName: "folder") }
            ActivityTab()
                .tabItem { Image(systemName: "waveform") }
            PreferenceTab()
                .tabItem { Image(systemName: "gearshape") }
        }
    }
}

// MARK: - Home tab

struct HomeTab: View {
    var body: some View {
        NavigationStack {
            Text("Home")
                .navigationTitle("Home")
        }
    }
}

// MARK: - Category tab

private enum CategoryDest: Hashable {
    case assets(UUID)
    case propertyDefs(UUID)
}

struct CategoryTab: View {
    @Environment(AssetStore.self) private var store
    @State private var navigationPath = NavigationPath()
    @State private var expandedCategoryID: UUID?
    @State private var newCategoryPresented = false
    @State private var assetToEdit: Asset?

    private var sortedCategories: [AssetCategory] {
        store.allCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if store.allCategories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "folder",
                        description: Text("Tap + to create your first category.")
                    )
                } else {
                    List(sortedCategories) { category in
                        CategoryRow(
                            category: category,
                            isExpanded: expandedCategoryID == category.id,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedCategoryID = expandedCategoryID == category.id ? nil : category.id
                                }
                            },
                            onNewAsset: {
                                let count = (try? store.assets(ofCategoryID: category.id))?.count ?? 0
                                let defaultName = "\(category.name) \(count + 1)"
                                if let asset = try? store.createAsset(name: defaultName, categoryID: category.id) {
                                    assetToEdit = asset
                                }
                            },
                            onViewAssets: { navigationPath.append(CategoryDest.assets(category.id)) },
                            onViewDefs: { navigationPath.append(CategoryDest.propertyDefs(category.id)) }
                        )
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newCategoryPresented = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: CategoryDest.self) { dest in
                switch dest {
                case .assets(let id):
                    if let cat = store.categories[id] { CategoryAssetsView(category: cat) }
                case .propertyDefs(let id):
                    if let cat = store.categories[id] { CategoryPropertyDefsView(category: cat) }
                }
            }
            .sheet(isPresented: $newCategoryPresented) { NewCategoryView() }
            .sheet(item: $assetToEdit) { asset in NavigationStack { AssetEditView(asset: asset) } }
        }
    }
}

// MARK: - Category row

private struct CategoryRow: View {
    let category: AssetCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    let onNewAsset: () -> Void
    let onViewAssets: () -> Void
    let onViewDefs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onToggle) {
                    Text(category.name)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onNewAsset) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                HStack(spacing: 32) {
                    Button(action: onViewAssets) {
                        VStack(spacing: 4) {
                            Image(systemName: "shippingbox")
                                .imageScale(.large)
                            Text("Assets")
                                .font(.caption2)
                        }
                    }
                    Button(action: onViewDefs) {
                        VStack(spacing: 4) {
                            Image(systemName: "list.bullet.clipboard")
                                .imageScale(.large)
                            Text("Definitions")
                                .font(.caption2)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category assets list

struct CategoryAssetsView: View {
    let category: AssetCategory

    var body: some View {
        Text("Assets in \(category.name)")
            .navigationTitle("Assets")
    }
}

// MARK: - Category property definitions

struct CategoryPropertyDefsView: View {
    let category: AssetCategory

    var body: some View {
        List(category.propertyTemplates) { prop in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(prop.definition.name)
                    Spacer()
                    if prop.definition.isRequired {
                        Text("required")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.12))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                    }
                }
                Text(prop.definition.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("Property Definitions")
    }
}

// MARK: - Activity tab

struct ActivityTab: View {
    var body: some View {
        NavigationStack {
            Text("Activity")
                .navigationTitle("Activity")
        }
    }
}

// MARK: - Preference tab

struct PreferenceTab: View {
    var body: some View {
        NavigationStack {
            Text("Preferences")
                .navigationTitle("Preferences")
        }
    }
}

// MARK: - Stub sheets

struct NewCategoryView: View {
    var body: some View {
        NavigationStack {
            Text("New Category")
                .navigationTitle("New Category")
        }
    }
}

// MARK: - Preview

#Preview {
    let store = AssetStore()
    store.seedBuiltInComboLists()
    store.seedBuiltInCategories()
    let catID = store.allCategories.first!.id
    try? store.createAsset(name: "2022 Toyota Camry", categoryID: catID)
    try? store.createAsset(name: "Bosch Refrigerator", categoryID: catID)
    return ContentView()
        .environment(store)
}
