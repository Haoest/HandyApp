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
        ("",        "System default"),
        ("en",      "English"),
        ("es",      "Español"),
        ("fr",      "Français"),
        ("zh-Hans", "简体中文"),
    ]
}

extension Locale {
    /// The locale the in-app language override (`AppPreference.languageKey`) resolves to.
    ///
    /// `.environment(\.locale, …)` (set once at the app root) only affects `LocalizedStringKey`
    /// lookups inside SwiftUI view bodies. `String(localized:)` resolves interpolation
    /// formatting and plural rules against this `locale:` argument, but its *table lookup* goes
    /// through `bundle:` (see `Bundle.appPreferred`) — pass both at any call site outside the
    /// view-rendering pass, or the override changes numbers/dates but not the translated text.
    static var appPreferred: Locale {
        let code = UserDefaults.standard.string(forKey: AppPreference.languageKey) ?? ""
        return code.isEmpty ? .autoupdatingCurrent : Locale(identifier: code)
    }
}

extension Bundle {
    private static var lprojCache: [String: Bundle] = [:]

    /// The `.lproj` bundle for the in-app language override, or `.main` when there is no
    /// override or the language ships no resources of its own. `Localizable.xcstrings`
    /// compiles to one `<code>.lproj/Localizable.strings` per language, so honoring the
    /// override is a bundle lookup — `String(localized:, locale:)`'s `locale:` argument only
    /// drives interpolation formatting, never which translation table is read.
    static var appPreferred: Bundle {
        let code = UserDefaults.standard.string(forKey: AppPreference.languageKey) ?? ""
        guard !code.isEmpty else { return .main }
        if let cached = lprojCache[code] { return cached }
        let resolved = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        lprojCache[code] = resolved
        return resolved
    }
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
