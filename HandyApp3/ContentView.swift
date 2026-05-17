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

// MARK: - Asset tab

struct AssetTab: View {
    @Environment(AssetStore.self) private var store
    @State private var newAssetPresented = false

    private var sortedAssets: [Asset] {
        store.allAssets.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.allAssets.isEmpty {
                    ContentUnavailableView(
                        "No Assets",
                        systemImage: "shippingbox",
                        description: Text("Tap + to add your first asset.")
                    )
                } else {
                    List(sortedAssets) { asset in
                        NavigationLink(destination: Text(asset.name)) {
                            AssetRow(asset: asset)
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
                NewAssetView()
            }
        }
    }
}

// MARK: - Category tab

struct CategoryTab: View {
    var body: some View {
        NavigationStack {
            Text("Categories")
                .navigationTitle("Categories")
        }
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

// MARK: - Stub sheets

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
