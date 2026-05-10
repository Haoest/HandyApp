import Foundation

/// Type-safe recursive value container for property values.
indirect enum StoredValue: Equatable {
    case text(String)
    case number(Double)
    case currency(Decimal)
    case date(Date)
    /// Stores a CNContact.identifier — resolve to a live contact via ContactResolver.
    case contact(String)
    /// Keyed by field name, mirrors a CompositeTypeDefinition's fields.
    case composite([String: StoredValue])

    var basicType: BasicType? {
        switch self {
        case .text:      return .text
        case .number:    return .number
        case .currency:  return .currency
        case .date:      return .date
        case .contact:   return .contact
        case .composite: return nil
        }
    }
}
