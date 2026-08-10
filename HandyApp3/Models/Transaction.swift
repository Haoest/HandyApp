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

    init(id: UUID = UUID(), details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String? = nil, notes: String = "", recurrence: RecurrenceInterval? = nil, modifyDate: Date = Date()) {
        self.id = id
        self.details = details
        self.amount = abs(amount)
        self.date = date
        self.kind = kind
        self.payeeContactID = payeeContactID
        self.notes = notes
        self.recurrence = recurrence
        self.modifyDate = modifyDate
    }

    /// Stamps the transaction as edited now. Called from AssetStore after any write.
    func touch(_ date: Date = Date()) {
        modifyDate = date
    }

    static func == (lhs: Transaction, rhs: Transaction) -> Bool { lhs.id == rhs.id }
}
