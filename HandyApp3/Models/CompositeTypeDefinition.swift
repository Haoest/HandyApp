import Foundation

// MARK: - Scope

/// Determines which assets can use a composite type.
/// Currently only `.global` exists; the enum is retained as a placeholder and is
/// removed entirely in Phase 5 of the AssetCategory → TypeNode migration.
enum CompositeTypeScope: Equatable {
    /// Available to assets of any type.
    case global
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

    /// When `false`, users cannot add, edit, or remove fields on this composite type.
    /// Built-in types like W × L should set this to `false`.
    let isUserExtensible: Bool

    var scope: CompositeTypeScope

    init(
        id: UUID = UUID(),
        name: String,
        systemFields: [PropertyDefinition] = [],
        userFields: [PropertyDefinition] = [],
        isUserExtensible: Bool = true,
        scope: CompositeTypeScope = .global
    ) {
        self.id = id
        self.name = name
        self.systemFields = systemFields
        self.userFields = userFields
        self.isUserExtensible = isUserExtensible
        self.scope = scope
    }

    static func == (lhs: CompositeTypeDefinition, rhs: CompositeTypeDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
