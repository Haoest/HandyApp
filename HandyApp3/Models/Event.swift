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

    /// Optional due date, independent of `date` (the event's own scheduled day).
    var dueDate: Date? = nil
    /// Shared identifier for a chain of duplicates of a recurring event — see `SeriesLogic`.
    var seriesID: UUID? = nil
    /// Instant this record was created (not edited); series members are ordered by this,
    /// independent of `modifyDate`.
    var createdAt: Date
    var messageDaysBefore: Int
    var messageDaysAfter: Int
    var deviceNotificationOn: Bool
    var deviceNotificationDaysBefore: Int

    init(id: UUID = UUID(), title: String, date: Date, notes: String = "", recurrence: RecurrenceInterval? = nil,
         dueDate: Date? = nil, seriesID: UUID? = nil, createdAt: Date = Date(),
         messageDaysBefore: Int = DueDefaults.messageDaysBefore,
         messageDaysAfter: Int = DueDefaults.messageDaysAfter,
         deviceNotificationOn: Bool = false,
         deviceNotificationDaysBefore: Int = DueDefaults.notifyDaysBefore,
         modifyDate: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
        self.notes = notes
        self.recurrence = recurrence
        self.dueDate = dueDate
        self.seriesID = seriesID
        self.createdAt = createdAt
        self.messageDaysBefore = messageDaysBefore
        self.messageDaysAfter = messageDaysAfter
        self.deviceNotificationOn = deviceNotificationOn
        self.deviceNotificationDaysBefore = deviceNotificationDaysBefore
        self.modifyDate = modifyDate
    }

    /// Stamps the event as edited now. Called from AssetStore after any write.
    func touch(_ date: Date = Date()) {
        modifyDate = date
    }

    static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
}
