import SwiftUI

// MARK: - Root

struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
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

/// UserDefaults keys for user preferences.
enum AppPreference {
    /// Caps on non-recurring events/transactions shown inline on the asset
    /// detail screen before the "Show All" row appears.
    static let eventLimitKey = "nonRecurringEventLimit"
    static let transactionLimitKey = "nonRecurringTransactionLimit"
    static let nonRecurringLimitDefault = 12
    static let nonRecurringLimitRange = 6.0...24.0
}

struct PreferenceTab: View {
    @AppStorage(AppPreference.eventLimitKey)
    private var eventLimit = AppPreference.nonRecurringLimitDefault
    @AppStorage(AppPreference.transactionLimitKey)
    private var transactionLimit = AppPreference.nonRecurringLimitDefault

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset Detail") {
                    LimitSlider(title: "Events to show", value: $eventLimit)
                    LimitSlider(title: "Transactions to show", value: $transactionLimit)
                }
            }
            .navigationTitle("Preferences")
        }
    }
}

private struct LimitSlider: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: AppPreference.nonRecurringLimitRange,
                step: 1
            )
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
        .environment(AppRouter())
}
