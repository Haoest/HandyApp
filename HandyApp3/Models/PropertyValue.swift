//
//  PropertyValue.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

// MARK: - StoredValue

/// A type-safe recursive value container matching the BasicType / composite hierarchy.
indirect enum StoredValue: Equatable {
    case text(String)
    case number(Double)
    case currency(Decimal)
    case date(Date)
    /// Stores a CNContact.identifier — a stable string that survives app relaunches.
    /// Resolve to a live CNContact via ContactResolver.
    case contact(String)
    /// Keyed by field name, mirrors a CompositeTypeDefinition's fields.
    case composite([String: StoredValue])

    /// Maps self back to the corresponding BasicType, or nil for composite.
    var basicType: BasicType? {
        switch self {
        case .text:    return .text
        case .number:  return .number
        case .currency: return .currency
        case .date:    return .date
        case .contact: return .contact
        case .composite: return nil
        }
    }
}

// MARK: - PropertyValue

/// A concrete value recorded on an Asset for a specific PropertyDefinition.
struct PropertyValue: Identifiable, Equatable {
    let id: UUID
    /// Links back to the PropertyDefinition (by id) that this value satisfies.
    var definitionID: UUID
    var value: StoredValue

    init(id: UUID = UUID(), definitionID: UUID, value: StoredValue) {
        self.id = id
        self.definitionID = definitionID
        self.value = value
    }
}
