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

    init(id: UUID = UUID(), details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String? = nil, notes: String = "", recurrence: RecurrenceInterval? = nil) {
        self.id = id
        self.details = details
        self.amount = abs(amount)
        self.date = date
        self.kind = kind
        self.payeeContactID = payeeContactID
        self.notes = notes
        self.recurrence = recurrence
    }

    static func == (lhs: Transaction, rhs: Transaction) -> Bool { lhs.id == rhs.id }
}
