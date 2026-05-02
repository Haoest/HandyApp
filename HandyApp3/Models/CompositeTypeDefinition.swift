//
//  CompositeTypeDefinition.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

// MARK: - Scope

/// Determines which assets can use a composite type.
enum CompositeTypeScope: Equatable {
    /// Available to assets across all categories.
    case global
    /// Restricted to assets belonging to the specified category.
    case category(AssetCategory)
}

// MARK: - CompositeTypeDefinition

/// A user-defined composite property type assembled from an ordered list of named fields.
/// Each field is itself a `PropertyDefinition`, so nesting composites is supported.
final class CompositeTypeDefinition: Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Ordered fields that make up this composite type.
    var fields: [PropertyDefinition]
    var scope: CompositeTypeScope

    init(
        id: UUID = UUID(),
        name: String,
        fields: [PropertyDefinition] = [],
        scope: CompositeTypeScope = .global
    ) {
        self.id = id
        self.name = name
        self.fields = fields
        self.scope = scope
    }

    static func == (lhs: CompositeTypeDefinition, rhs: CompositeTypeDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
