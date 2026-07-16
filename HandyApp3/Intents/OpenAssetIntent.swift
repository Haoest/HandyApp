import AppIntents

struct OpenAssetIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Asset"
    static let openAppWhenRun = true

    @Parameter(title: "Asset")
    var asset: AssetEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.selectedTab = .assets
        deps.router.pendingAssetID = asset.id
        return .result()
    }
}
