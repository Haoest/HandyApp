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
            ToolsTab()
                .tabItem { Image(systemName: "wrench.and.screwdriver") }
                .tag(AppTab.tools)
            PreferenceTab()
                .tabItem { Image(systemName: "gearshape") }
                .tag(AppTab.preferences)
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

    /// How many days a soft-deleted asset or category is kept before hard deletion.
    static let deletedRetentionDaysKey = "deletedRetentionDays"
    static let deletedRetentionDaysDefault = 14
    static let deletedRetentionDaysRange = 7.0...30.0
}

struct PreferenceTab: View {
    @Environment(AssetStore.self) private var store
    @AppStorage(AppPreference.eventLimitKey)
    private var eventLimit = AppPreference.nonRecurringLimitDefault
    @AppStorage(AppPreference.transactionLimitKey)
    private var transactionLimit = AppPreference.nonRecurringLimitDefault
    @AppStorage(AppPreference.deletedRetentionDaysKey)
    private var deletedRetentionDays = AppPreference.deletedRetentionDaysDefault

    var body: some View {
        @Bindable var store = store
        return NavigationStack {
            ZStack {
                AppBackground()
                Form {
                    Section("Appearance") {
                        Picker("Background", selection: $store.backgroundTheme) {
                            ForEach(BackgroundTheme.allCases) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.white.opacity(0.5))
                    Section("Asset Detail") {
                        LimitSlider(title: "Events to show", value: $eventLimit)
                        LimitSlider(title: "Transactions to show", value: $transactionLimit)
                    }
                    .listRowBackground(Color.white.opacity(0.5))
                    Section("Data") {
                        RetentionSlider(days: $deletedRetentionDays)
                    }
                    .listRowBackground(Color.white.opacity(0.5))
                }
                .scrollContentBackground(.hidden)
                // Background is always a light gradient — pin the scheme light so the
                // form's labels stay dark for contrast even in system dark mode.
                .environment(\.colorScheme, .light)
            }
            .navigationTitle("Preferences")
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
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

private struct RetentionSlider: View {
    @Binding var days: Int

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Keep deleted items for")
                Spacer()
                Text("\(days) days")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(days) },
                    set: { days = Int($0) }
                ),
                in: AppPreference.deletedRetentionDaysRange,
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
