import AppIntents

/// Opens the things list, pushing straight to one thing when the caller supplied it.
///
/// `asset` is optional so the Spotlight tile works with no argument: Siri never has to ask
/// which thing. The Shortcuts app still offers a picker for it, where a parameter costs
/// nothing.
struct OpenAssetIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Things"
    static let openAppWhenRun = true

    @Parameter(title: "Thing")
    var asset: AssetEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.selectedTab = .assets
        // nil leaves the user on the list — navigationDestination(item:) pushes nothing.
        deps.router.pendingAssetID = asset?.id
        return .result()
    }
}
