import Foundation

enum RecurrenceInterval: String, CaseIterable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case semiAnnually = "Semi-Annually"
    case annually = "Annually"
    case biAnnually = "Bi-Annually"

    var componentAndValue: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: (.weekOfYear, 1)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .semiAnnually: (.month, 6)
        case .annually: (.year, 1)
        case .biAnnually: (.year, 2)
        }
    }

    /// Localized label for the recurrence chip picker. `rawValue` stays English and unlocalized
    /// on purpose — it's persisted and synced (see `EventDTO.recurrence`/`TransactionDTO.recurrence`
    /// in `Persistence.swift`), so it can't follow the display language.
    var displayName: String {
        switch self {
        case .weekly: String(localized: "Weekly", locale: .appPreferred)
        case .monthly: String(localized: "Monthly", locale: .appPreferred)
        case .quarterly: String(localized: "Quarterly", locale: .appPreferred)
        case .semiAnnually: String(localized: "Semi-annually", locale: .appPreferred)
        case .annually: String(localized: "Annually", locale: .appPreferred)
        case .biAnnually: String(localized: "Bi-annually", locale: .appPreferred)
        }
    }

    /// Compact schedule-code form for tight display contexts (e.g. the Logs tab's series list).
    /// Not localized — `rawValue` isn't either (see its doc), so this stays consistent with it.
    var abbreviation: String {
        switch self {
        case .weekly: "W"
        case .monthly: "M"
        case .quarterly: "Q"
        case .semiAnnually: "6M"
        case .annually: "Y"
        case .biAnnually: "2Y"
        }
    }
}
