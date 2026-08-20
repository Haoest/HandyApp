import SwiftUI

// MARK: - Root

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AssetStore.self) private var store

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .top) {
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
            if store.storeRequiresNewerApp {
                UpdateRequiredBanner()
            } else if store.savesSuspended {
                SyncSuspendedBanner()
            }
        }
        .animation(.default, value: store.savesSuspended)
        .animation(.default, value: store.storeRequiresNewerApp)
    }
}

/// Shown when this build is older than whatever last wrote the store — see
/// `AssetStore.storeRequiresNewerApp`. Takes priority over `SyncSuspendedBanner`: both reflect
/// a store that currently can't be written to, but this one means an app update is required,
/// not just a wait.
private struct UpdateRequiredBanner: View {
    var body: some View {
        Label("Update the app to keep editing — changes aren't being saved", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .shadow(radius: 2)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Shown while the store has only ever seeded sample data and is withholding saves until it
/// confirms whether the iCloud container already has real data — see
/// `AssetStore.savesSuspended`. Without this, a device stuck in that state (e.g. a shard that
/// never finishes downloading) silently discards every edit the user makes with no visible sign
/// anything is wrong.
private struct SyncSuspendedBanner: View {
    var body: some View {
        Label("Waiting for iCloud…", systemImage: "icloud.and.arrow.down")
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .shadow(radius: 2)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Preference tab

struct PreferenceTab: View {
    @Environment(AssetStore.self) private var store
    @AppStorage(AppPreference.eventLimitKey)
    private var eventLimit = AppPreference.nonRecurringLimitDefault
    @AppStorage(AppPreference.transactionLimitKey)
    private var transactionLimit = AppPreference.nonRecurringLimitDefault
    @AppStorage(AppPreference.languageKey)
    private var languageCode: String = ""

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
                    Section("Language") {
                        Picker("Language", selection: $languageCode) {
                            ForEach(AppPreference.supportedLanguages, id: \.code) { lang in
                                Text(lang.label).tag(lang.code)
                            }
                        }
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
    let title: LocalizedStringKey
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
