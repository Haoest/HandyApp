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
