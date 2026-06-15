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
                .tabItem { Image(systemName: "wrench.and.screwdriver") }
                .tag(AppTab.tools)
            PreferenceTab()
                .tabItem { Image(systemName: "gearshape") }
                .tag(AppTab.preferences)
        }
    }
}

// MARK: - Activity tab

struct ActivityTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark backdrop so the colored dust reads vividly.
                RadialGradient(
                    colors: [Color(red: 0.10, green: 0.11, blue: 0.18), .black],
                    center: .center, startRadius: 0, endRadius: 600
                )
                .ignoresSafeArea()
                DustBallView()
            }
            .navigationTitle("Tools")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
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
    @Environment(AssetStore.self) private var store
    @AppStorage(AppPreference.eventLimitKey)
    private var eventLimit = AppPreference.nonRecurringLimitDefault
    @AppStorage(AppPreference.transactionLimitKey)
    private var transactionLimit = AppPreference.nonRecurringLimitDefault

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
