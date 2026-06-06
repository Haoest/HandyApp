import SwiftUI

// MARK: - Root

struct ContentView: View {
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeTab()
                .tabItem { Image(systemName: "house") }
                .tag(AppTab.home)
            AssetTab()
                .tabItem { Image(systemName: "shippingbox") }
                .tag(AppTab.assets)
            CategoryTab()
                .tabItem { Image(systemName: "folder") }
                .tag(AppTab.categories)
            ActivityTab()
                .tabItem { Image(systemName: "waveform") }
                .tag(AppTab.activity)
            PreferenceTab()
                .tabItem { Image(systemName: "gearshape") }
                .tag(AppTab.preferences)
        }
        .environment(router)
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
