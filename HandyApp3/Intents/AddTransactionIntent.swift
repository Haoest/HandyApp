import AppIntents

struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction"
    static let openAppWhenRun = true

    @Parameter(title: "Asset")
    var asset: AssetEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.pendingTransactionKind = .expense
        deps.router.pendingAssetID = asset.id
        deps.router.selectedTab = .assets
        return .result()
    }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let openAppWhenRun = true

    @Parameter(title: "Asset")
    var asset: AssetEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.pendingTransactionKind = .expense
        deps.router.pendingAssetID = asset.id
        deps.router.selectedTab = .assets
        return .result()
    }
}

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Income"
    static let openAppWhenRun = true

    @Parameter(title: "Asset")
    var asset: AssetEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.pendingTransactionKind = .income
        deps.router.pendingAssetID = asset.id
        deps.router.selectedTab = .assets
        return .result()
    }
}
