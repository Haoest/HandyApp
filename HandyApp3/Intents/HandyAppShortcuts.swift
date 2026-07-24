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
                "Add new asset in \(.applicationName)"
            ],
            shortTitle: "Add Asset",
            systemImageName: "plus.circle"
        )
    }
}
