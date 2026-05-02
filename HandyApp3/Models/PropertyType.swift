//
//  PropertyType.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

// MARK: - Basic primitive types

enum BasicType: String, CaseIterable, Equatable, Hashable, Codable {
    case text
    case number
    case currency
    case date
}

// MARK: - Property type (basic or composite, recursive)

indirect enum PropertyType: Equatable {
    case basic(BasicType)
    case composite(CompositeTypeDefinition)

    var displayName: String {
        switch self {
        case .basic(let b): return b.rawValue.capitalized
        case .composite(let c): return c.name
        }
    }

    var isComposite: Bool {
        if case .composite = self { return true }
        return false
    }
}
