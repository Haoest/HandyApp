import AppIntents

struct AddAssetIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Asset"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.selectedTab = .assets
        deps.router.pendingNewAsset = true
        return .result()
    }
}
