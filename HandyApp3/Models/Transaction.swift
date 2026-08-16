import Foundation
import Observation

enum TransactionKind: String, CaseIterable {
    case expense = "Expense"
    case income = "Income"
}

@Observable
final class Transaction: Identifiable, Equatable {
    let id: UUID
    var details: String
    var amount: Decimal
    var date: Date
    var kind: TransactionKind
    var payeeContactID: String?
    var notes: String
    var recurrence: RecurrenceInterval?

    /// Absolute instant of the last edit to this transaction, including its tombstoning.
    /// `Date` is timezone-free; persisted as ISO-8601 UTC.
    var modifyDate: Date

    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    /// Optional due date, independent of `date` (the transaction's own occurrence day).
    var dueDate: Date? = nil
    /// Shared identifier for a chain of duplicates of a recurring transaction — see `SeriesLogic`.
    var seriesID: UUID? = nil
    /// Instant this record was created (not edited); series members are ordered by this,
    /// independent of `modifyDate`.
    var createdAt: Date
    var messageDaysBefore: Int
    var messageDaysAfter: Int
    var deviceNotificationOn: Bool
    var deviceNotificationDaysBefore: Int

    init(id: UUID = UUID(), details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String? = nil, notes: String = "", recurrence: RecurrenceInterval? = nil,
         dueDate: Date? = nil, seriesID: UUID? = nil, createdAt: Date = Date(),
         messageDaysBefore: Int = DueDefaults.messageDaysBefore,
         messageDaysAfter: Int = DueDefaults.messageDaysAfter,
         deviceNotificationOn: Bool = false,
         deviceNotificationDaysBefore: Int = DueDefaults.notifyDaysBefore,
         modifyDate: Date = Date()) {
        self.id = id
        self.details = details
        self.amount = abs(amount)
        self.date = date
        self.kind = kind
        self.payeeContactID = payeeContactID
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

    /// Stamps the transaction as edited now. Called from AssetStore after any write.
    func touch(_ date: Date = Date()) {
        modifyDate = date
    }

    static func == (lhs: Transaction, rhs: Transaction) -> Bool { lhs.id == rhs.id }
}
