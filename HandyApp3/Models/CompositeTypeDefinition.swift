import Foundation

// MARK: - CompositeTypeDefinition

/// A composite *value* type assembled from named fields (e.g. W × L, an Address struct).
/// Distinct from `TypeNode`, which describes what kind of object an `Asset` is —
/// `CompositeTypeDefinition` describes the shape of a structured value.
///
/// Fields are split into two groups:
/// - `systemFields` — predefined by the template; cannot be removed or edited by the user.
/// - `userFields`   — freely added, edited, or removed by the user at any time.
///
/// The computed `fields` (= systemFields + userFields) is used everywhere
/// validation and storage occur.
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

    init(
        id: UUID = UUID(),
        name: String,
        systemFields: [PropertyDefinition] = [],
        userFields: [PropertyDefinition] = [],
        isUserExtensible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.systemFields = systemFields
        self.userFields = userFields
        self.isUserExtensible = isUserExtensible
    }

    static func == (lhs: CompositeTypeDefinition, rhs: CompositeTypeDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
