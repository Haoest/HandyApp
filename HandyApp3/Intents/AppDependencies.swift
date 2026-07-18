import Foundation

/// Shared access point for App Intents, which run outside the SwiftUI view tree and
/// can't reach `.environment(...)` values. `HandyApp3App` reads `router`/`store` from
/// here instead of constructing its own, so intents and the UI always share the same
/// live instances regardless of process/launch path.
@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    let router = AppRouter()
    lazy var store: AssetStore = Self.makeStore()

    private init() {}

    private static func makeStore() -> AssetStore {
        let s = AssetStore()
        // File I/O runs on background thread internally; blocks main briefly (store.json is tiny)
        let wasLoaded = s.load()
        // Built-in seeds are idempotent — always run to pick up new types added in app updates
        s.seedBuiltInComboLists()
        s.seedBuiltInCategories()
        s.seedBuiltInTypes()
        switch AssetStore.coldStartAction(
            loaded: wasLoaded,
            iCloudActive: AssetStore.iCloudSyncEnabled
                && FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
        ) {
        case .useLoaded:
            s.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
            DispatchQueue.global(qos: .background).async { s.save() }
        case .seedAndPersist:
            s.seedBuiltInAssets()
            s.seedSampleAutomobile()
            DispatchQueue.global(qos: .background).async { s.save() }
        case .seedSuspended:
            s.seedBuiltInAssets()
            s.seedSampleAutomobile()
            s.savesSuspended = true
            // Do NOT save — cloud may have real data; savesSuspended lifts when cloud answers.
        }
        s.notificationScheduler = NotificationScheduler()
        return s
    }
}
