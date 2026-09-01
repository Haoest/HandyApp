import AppIntents

struct HandyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAssetIntent(),
            phrases: [
                "Open \(.applicationName) thing \(\.$asset)",
                "Open \(\.$asset) in \(.applicationName)",
                "Show \(\.$asset) in \(.applicationName)",
                "Open a thing in \(.applicationName)"
            ],
            shortTitle: "Open Thing",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: AddAssetIntent(),
            phrases: [
                "Add thing in \(.applicationName)",
                "Add new thing in \(.applicationName)",
                "Create thing in \(.applicationName)",
                "Create new thing in \(.applicationName)"
            ],
            shortTitle: "Add Thing",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddNamedAssetIntent(),
            phrases: [
                "Add new named thing in \(.applicationName)",
                "Create new named thing in \(.applicationName)"
            ],
            shortTitle: "Add Named Thing",
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
