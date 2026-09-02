import AppIntents

/// The three actions that surface as tappable tiles when the user searches the app name in
/// Spotlight.
///
/// Every shortcut is parameter-free and carries exactly one phrase. An `AppShortcut` cannot
/// be declared without a phrase — the phrase is what registers the Spotlight tile, and
/// there is no API to keep the tile while opting out of voice. Keeping them short and
/// argument-free is what removes the spoken follow-up questions.
struct HandyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogIntent(),
            phrases: ["Log in \(.applicationName)"],
            shortTitle: "Log",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenAssetIntent(),
            phrases: ["Open things in \(.applicationName)"],
            shortTitle: "Open Things",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: AddAssetIntent(),
            phrases: ["New thing in \(.applicationName)"],
            shortTitle: "New Thing",
            systemImageName: "plus.circle"
        )
    }
}
