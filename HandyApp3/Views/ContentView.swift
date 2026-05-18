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
