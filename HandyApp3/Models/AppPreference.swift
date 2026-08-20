import Foundation

/// UserDefaults keys for user preferences.
enum AppPreference {
    /// Caps on non-recurring events/transactions shown inline on the asset
    /// detail screen before the "Show All" row appears.
    static let eventLimitKey = "nonRecurringEventLimit"
    static let transactionLimitKey = "nonRecurringTransactionLimit"
    static let nonRecurringLimitDefault = 12
    static let nonRecurringLimitRange = 6.0...24.0

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
