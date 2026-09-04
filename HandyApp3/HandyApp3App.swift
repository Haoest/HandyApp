import CoreSpotlight
import SwiftUI

@main
struct HandyApp3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreference.languageKey) private var languageCode: String = ""
    @AppStorage(AppPreference.appearanceKey) private var appearance: String = ""
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
                // Applied at the root so sheets and pushed screens, which inherit the
                // presenting environment, follow it too.
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
                .task {
                    store.notificationScheduler?.onOpenAsset = { assetID, kind in
                        router.selectedTab = .assets
                        router.pendingAssetID = assetID
                        switch kind {
                        case .event: router.pendingAssetAnchor = .events
                        case .transaction: router.pendingAssetAnchor = .transactions
                        case nil: router.pendingAssetAnchor = nil
                        }
                    }
                    store.startCloudMonitor()
                    store.requestDerivedResync()
                    purchases.start()
                    store.assetCreationLimit = purchases.isFullVersion ? nil : PurchaseManager.freeAssetLimit
                    store.recordCreationLimit = purchases.isFullVersion ? nil : PurchaseManager.freeRecordLimit
                    HandyAppShortcuts.updateAppShortcutParameters()
                }
                // Tapping a thing in Spotlight. The identifier is the asset's UUID string
                // (see SpotlightIndexer), and pendingAssetID is the same deep-link path the
                // notification tap and OpenAssetIntent use — a stale id degrades to the
                // "Thing not found" view rather than doing nothing.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let id = UUID(uuidString: raw) else { return }
                    router.selectedTab = .assets
                    router.pendingAssetID = id
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                DispatchQueue.global(qos: .background).async { store.save() }
            }
            if phase == .background { HandyAppShortcuts.updateAppShortcutParameters() }
            if phase == .active {
                store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
                store.requestDerivedResync()
                DispatchQueue.global(qos: .background).async { store.save() }
            }
        }
        .onChange(of: purchases.isFullVersion) { _, unlocked in
            store.assetCreationLimit = unlocked ? nil : PurchaseManager.freeAssetLimit
            store.recordCreationLimit = unlocked ? nil : PurchaseManager.freeRecordLimit
        }
        .onChange(of: languageCode) { _, _ in
            // Notification bodies and the Spotlight home-screen shortcut title are resolved and
            // baked in at schedule time, not read fresh at delivery — a language switch alone
            // never touches them, so both need an explicit refresh here.
            store.requestDerivedResync()
            HandyAppShortcuts.updateAppShortcutParameters()
        }
    }
}
