import Foundation
import Observation

@Observable
final class Event: Identifiable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    var notes: String
    var recurrence: RecurrenceInterval?

    init(id: UUID = UUID(), title: String, date: Date, notes: String = "", recurrence: RecurrenceInterval? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.notes = notes
        self.recurrence = recurrence
    }

    static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
}
