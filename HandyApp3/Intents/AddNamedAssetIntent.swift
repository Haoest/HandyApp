import AppIntents

struct AddNamedAssetIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Named Asset"
    static let openAppWhenRun = true

    @Parameter(
        title: "Name",
        requestValueDialog: IntentDialog("What would you like to name the new asset?")
    )
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.pendingNewAssetName = name
        deps.router.selectedTab = .assets
        deps.router.pendingNewAsset = true
        return .result()
    }
}
