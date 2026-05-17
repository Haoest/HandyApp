import SwiftUI

// MARK: - Menu data model

struct HomeMenuAction: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let destination: HomeDestination

    static let all: [HomeMenuAction] = [
        .init(id: "newAsset",    label: "New Asset",    systemImage: "plus.circle",      destination: .newAsset),
        .init(id: "newCategory", label: "New Category", systemImage: "folder.badge.plus", destination: .newCategory),
        .init(id: "preferences", label: "Preferences",  systemImage: "gearshape",         destination: .preferences),
    ]
}

enum HomeDestination: String, Identifiable {
    case newAsset, newCategory, preferences
    var id: String { rawValue }
}

// MARK: - Home screen

struct ContentView: View {
    @Environment(AssetStore.self) private var store
    @State private var activeSheet: HomeDestination?

    private var sortedAssets: [Asset] {
        store.allAssets.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.allAssets.isEmpty {
                    emptyState
                } else {
                    assetList
                }
            }
            .navigationTitle("My Assets")
            .toolbar { menuButton }
            .sheet(item: $activeSheet, content: sheetContent)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Assets Yet",
            systemImage: "shippingbox",
            description: Text("Use the menu to add your first asset.")
        )
    }

    private var assetList: some View {
        List(sortedAssets) { asset in
            NavigationLink(destination: Text(asset.name)) {
                AssetRow(asset: asset)
            }
        }
    }

    @ToolbarContentBuilder
    private var menuButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(HomeMenuAction.all) { action in
                    Button {
                        activeSheet = action.destination
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ destination: HomeDestination) -> some View {
        switch destination {
        case .newAsset:    NewAssetView()
        case .newCategory: NewCategoryView()
        case .preferences: PreferencesView()
        }
    }
}

// MARK: - Asset row

private struct AssetRow: View {
    let asset: Asset

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.name)
                .font(.body)
            HStack {
                Text(asset.category.name)
                Spacer()
                Text(asset.modifiedDate, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Destination stubs

struct NewAssetView: View {
    var body: some View {
        NavigationStack {
            Text("New Asset")
                .navigationTitle("New Asset")
        }
    }
}

struct NewCategoryView: View {
    var body: some View {
        NavigationStack {
            Text("New Category")
                .navigationTitle("New Category")
        }
    }
}

struct PreferencesView: View {
    var body: some View {
        NavigationStack {
            Text("Preferences")
                .navigationTitle("Preferences")
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
