import Foundation

/// UserDefaults keys for user preferences.
enum AppPreference {
    /// Caps on non-recurring events/transactions shown inline on the asset detail screen
    /// before the "Show All" row appears. Fixed at `nonRecurringLimitDefault` — the
    /// Preferences screen that used to let the user tune these was removed in favor of the
    /// Logs tab, but a value stored by that screen still applies.
    static let eventLimitKey = "nonRecurringEventLimit"
    static let transactionLimitKey = "nonRecurringTransactionLimit"
    static let nonRecurringLimitDefault = 12
    static let nonRecurringLimitRange = 6.0...24.0

    /// Filter controls on the Logs tab. `ledgerLateOnlyKey` is independent of
    /// `ledgerTypeFilterKey` — the two combine (e.g. events-only + late-only shows only late
    /// events), rather than being mutually exclusive options of one control.
    static let ledgerTypeFilterKey = "ledgerTypeFilter"
    static let ledgerLateOnlyKey = "ledgerLateOnly"
    static let ledgerWindowMonthsKey = "ledgerWindowMonths"
    static let ledgerWindowMonthsRange = 1...24

    /// How many days a soft-deleted asset or category is kept before hard deletion.
    static let DaysToRetainDeletedItems = 14

    /// Light/dark override; empty string = follow the device. See `AppearanceMode`.
    static let appearanceKey = "appearanceMode"

    /// BCP 47 language tag for locale override; empty string = system default.
    static let languageKey = "preferredLanguage"
    static let supportedLanguages: [(code: String, label: String)] = [
        ("",        "System Default"),
        ("en",      "English"),
        ("es",      "Español"),
        ("fr",      "Français"),
        ("zh-Hans", "简体中文"),
    ]
}

/// Whether the app follows the device's light/dark setting or pins one of them.
///
/// The raw values are what `@AppStorage` persists, and `system` is deliberately the empty
/// string: a device that has never touched this setting reads back "" and lands on `system`
/// without needing a registered default. Mapping to a `ColorScheme` is a view concern and
/// lives with the other Baron chrome.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = ""
    case light
    case dark

    var id: String { rawValue }
}
