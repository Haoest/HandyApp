import SwiftUI

@main
struct HandyApp3App: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    @State private var store: AssetStore = {
        let s = AssetStore()
        s.seedBuiltInComboLists()
        s.seedBuiltInCategories()
        s.seedBuiltInTypes()
        s.seedBuiltInAssets()
        s.seedSampleHVAC()
        s.seedSampleEvents()
        s.seedSampleTransactions()
        s.seedSamplePhotos()
        s.notificationScheduler = NotificationScheduler()
        return s
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .task {
                    store.notificationScheduler?.onOpenAsset = { assetID in
                        router.selectedTab = .assets
                        router.pendingAssetID = assetID
                    }
                    try? await ContactResolver.shared.requestAccess()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.notificationScheduler?.requestResync(assets: store.allAssets)
        }
    }
}
