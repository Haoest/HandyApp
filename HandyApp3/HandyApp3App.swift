import SwiftUI

@main
struct HandyApp3App: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreference.languageKey) private var languageCode: String = ""
    @State private var router = AppRouter()
    @State private var store: AssetStore = {
        let s = AssetStore()
        // File I/O runs on background thread internally; blocks main briefly (store.json is tiny)
        let wasLoaded = s.load()
        // Built-in seeds are idempotent — always run to pick up new types added in app updates
        s.seedBuiltInComboLists()
        s.seedBuiltInCategories()
        s.seedBuiltInTypes()
        if !wasLoaded {
            s.seedBuiltInAssets()
            s.seedSampleHVAC()
            s.seedSampleEvents()
            s.seedSampleTransactions()
            s.seedSamplePhotos()
        } else {
            let storedDays = UserDefaults.standard.integer(forKey: AppPreference.deletedRetentionDaysKey)
            let retentionDays = storedDays > 0 ? storedDays : AppPreference.deletedRetentionDaysDefault
            s.purgeHardDeleted(olderThan: TimeInterval(retentionDays) * 86_400)
        }
        DispatchQueue.global(qos: .background).async { s.save() }
        s.notificationScheduler = NotificationScheduler()
        return s
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(\.locale, languageCode.isEmpty ? .autoupdatingCurrent : Locale(identifier: languageCode))
                .task {
                    store.notificationScheduler?.onOpenAsset = { assetID in
                        router.selectedTab = .assets
                        router.pendingAssetID = assetID
                    }
                    try? await ContactResolver.shared.requestAccess()
                    store.startCloudMonitor()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                DispatchQueue.global(qos: .background).async { store.save() }
            }
            if phase == .active { store.notificationScheduler?.requestResync(assets: store.allAssets) }
        }
    }
}
