import SwiftUI

// MARK: - Root

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AssetStore.self) private var store

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .top) {
            TabView(selection: $router.selectedTab) {
                TimelineTab()
                    .tabItem { Label("Timeline", systemImage: "list.bullet.indent") }
                    .tag(AppTab.timeline)
                ThingsTab()
                    .tabItem { Label("Things", systemImage: "shippingbox") }
                    .tag(AppTab.assets)
                SetupTab()
                    .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
                    .tag(AppTab.setup)
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
