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

/// A composite property type assembled from named fields.
///
/// Fields are split into two groups:
/// - `systemFields` — predefined by the template; cannot be removed or edited by the user.
/// - `userFields`   — freely added, edited, or removed by the user at any time.
///
/// The computed `fields` (= systemFields + userFields) is used everywhere
/// validation and storage occurs — all existing code works unchanged.
final class CompositeTypeDefinition: Identifiable, Equatable {
    let id: UUID
    var name: String

    /// Predefined fields set at creation. Never removable by the user.
    private(set) var systemFields: [PropertyDefinition]

    /// Fields the user has freely added on top of the template.
    var userFields: [PropertyDefinition]

    /// All fields in order: system fields first, then user fields.
    /// Use this everywhere — validation, display, value storage.
    var fields: [PropertyDefinition] { systemFields + userFields }

    var scope: CompositeTypeScope

    init(
        id: UUID = UUID(),
        name: String,
        systemFields: [PropertyDefinition] = [],
        userFields: [PropertyDefinition] = [],
        scope: CompositeTypeScope = .global
    ) {
        self.id = id
        self.name = name
        self.systemFields = systemFields
        self.userFields = userFields
        self.scope = scope
    }

    static func == (lhs: CompositeTypeDefinition, rhs: CompositeTypeDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
