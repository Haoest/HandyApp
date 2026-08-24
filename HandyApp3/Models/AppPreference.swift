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
