import Foundation
import Observation

@Observable
final class Event: Identifiable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    var notes: String
    var recurrence: RecurrenceInterval?

    /// Absolute instant of the last edit to this event, including its tombstoning.
    /// `Date` is timezone-free; persisted as ISO-8601 UTC.
    var modifyDate: Date

    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    init(id: UUID = UUID(), title: String, date: Date, notes: String = "", recurrence: RecurrenceInterval? = nil, modifyDate: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
        self.notes = notes
        self.recurrence = recurrence
        self.modifyDate = modifyDate
    }

    /// Stamps the event as edited now. Called from AssetStore after any write.
    func touch(_ date: Date = Date()) {
        modifyDate = date
    }

    static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
}
