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

    /// Occurrence dates strictly after `referenceDate`, paired with their index from the
    /// base date. Occurrence i is always computed as baseDate + interval × i rather than
    /// by adding to the previous occurrence, so month-end clamping never accumulates
    /// (Jan 31 → Feb 28, Mar 31, Apr 30 — not Feb 28, Mar 28, Apr 28).
    func occurrences(from baseDate: Date, after referenceDate: Date, count: Int, calendar: Calendar = .current) -> [(index: Int, date: Date)] {
        guard count > 0 else { return [] }
        let (component, value) = componentAndValue
        var result: [(index: Int, date: Date)] = []
        var i = 0
        while result.count < count && i < 5000 {
            guard let date = calendar.date(byAdding: component, value: value * i, to: baseDate) else { break }
            if date > referenceDate {
                result.append((index: i, date: date))
            }
            i += 1
        }
        return result
    }
}
