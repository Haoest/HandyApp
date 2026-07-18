import SwiftUI

@main
struct HandyApp3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreference.languageKey) private var languageCode: String = ""
    @State private var router = AppDependencies.shared.router
    @State private var purchases = PurchaseManager()
    @State private var store = AppDependencies.shared.store

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(purchases)
                .environment(\.locale, languageCode.isEmpty ? .autoupdatingCurrent : Locale(identifier: languageCode))
                .task {
                    store.notificationScheduler?.onOpenAsset = { assetID in
                        router.selectedTab = .assets
                        router.pendingAssetID = assetID
                    }
                    try? await ContactResolver.shared.requestAccess()
                    store.startCloudMonitor()
                    purchases.start()
                    store.assetCreationLimit = purchases.isFullVersion ? nil : PurchaseManager.freeAssetLimit
                    store.eventCreationLimit = purchases.isFullVersion ? nil : PurchaseManager.freeEventLimit
                    store.transactionCreationLimit = purchases.isFullVersion ? nil : PurchaseManager.freeTransactionLimit
                    HandyAppShortcuts.updateAppShortcutParameters()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                DispatchQueue.global(qos: .background).async { store.save() }
            }
            if phase == .background { HandyAppShortcuts.updateAppShortcutParameters() }
            if phase == .active { store.notificationScheduler?.requestResync(assets: store.allAssets) }
        }
        .onChange(of: purchases.isFullVersion) { _, unlocked in
            store.assetCreationLimit = unlocked ? nil : PurchaseManager.freeAssetLimit
            store.eventCreationLimit = unlocked ? nil : PurchaseManager.freeEventLimit
            store.transactionCreationLimit = unlocked ? nil : PurchaseManager.freeTransactionLimit
        }
    }
}
