import AppIntents

struct HandyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAssetIntent(),
            phrases: [
                "Open \(.applicationName) asset \(\.$asset)",
                "Open \(\.$asset) in \(.applicationName)",
                "Show \(\.$asset) in \(.applicationName)",
                "Open an asset in \(.applicationName)"
            ],
            shortTitle: "Open Asset",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: AddAssetIntent(),
            phrases: [
                "Add asset in \(.applicationName)",
                "Add new asset in \(.applicationName)",
                "Create asset in \(.applicationName)",
                "Create new asset in \(.applicationName)"
            ],
            shortTitle: "Add Asset",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddNamedAssetIntent(),
            phrases: [
                "Add new named asset in \(.applicationName)",
                "Create new named asset in \(.applicationName)"
            ],
            shortTitle: "Add Named Asset",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add transaction to \(\.$asset) in \(.applicationName)",
                "Record transaction to \(\.$asset) in \(.applicationName)"
            ],
            shortTitle: "Add Transaction",
            systemImageName: "arrow.left.arrow.right.circle"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add expense to \(\.$asset) in \(.applicationName)",
                "Record expense to \(\.$asset) in \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Add income to \(\.$asset) in \(.applicationName)",
                "Record income to \(\.$asset) in \(.applicationName)"
            ],
            shortTitle: "Add Income",
            systemImageName: "plus.circle"
        )
    }
}
