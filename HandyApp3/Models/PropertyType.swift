import Foundation

// MARK: - Basic primitive types

enum BasicType: String, CaseIterable, Equatable, Hashable, Codable {
    case text
    case number
    case currency
    case date
    /// A reference to an iOS Contacts entry, stored as a CNContact.identifier string.
    case contact
    /// Raw binary data (Foundation.Data).
    case data
}

// MARK: - Property type (basic or composite, recursive)

indirect enum PropertyType: Equatable {
    case basic(BasicType)
    case composite(CompositeTypeDefinition)
    /// A pick-list of string choices; the stored value is one of the list's options.
    case comboList(ComboListDefinition)

    var displayName: String {
        switch self {
        case .basic(let b):      return b.rawValue.capitalized
        case .composite(let c):  return c.name
        case .comboList(let cl): return cl.name
        }
    }

    var isComposite: Bool {
        if case .composite = self { return true }
        return false
    }
}
