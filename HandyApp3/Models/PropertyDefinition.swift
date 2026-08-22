import Foundation

/// Describes a named, typed property slot. Used as a field on a `CompositeTypeDefinition`
/// or as the schema embedded in an `AssetProperty`.
struct PropertyDefinition: Identifiable, Equatable {
    let id: UUID
    var name: String
    var type: PropertyType
    /// When `false` the field may be omitted from a composite payload without a validation error.
    var isRequired: Bool
    /// Character bound for a `.basic(.text)` or `.comboList` value. `nil` only for a definition
    /// that predates this field (or a non-text type, where it is meaningless) — the UI never
    /// mints a `nil` for a text/comboList definition. See `acceptsMaxLength`/`clamped(_:)`.
    var maxLength: Int?

    init(id: UUID = UUID(), name: String, type: PropertyType, isRequired: Bool = true, maxLength: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.isRequired = isRequired
        self.maxLength = maxLength
    }
}

extension PropertyDefinition {
    /// Starting bound offered when a user creates a new text/comboList property.
    static let defaultTextMaxLength = 100

    /// Hard ceiling on a user-set `maxLength` — no category property or asset custom property
    /// may be configured with a bound above this, enforced both in the property editor sheet
    /// and (defensively) wherever `AssetStore` writes a caller-supplied `maxLength`.
    static let systemMaxLength = 2000

    /// Whether this definition's value is a bounded string — `.basic(.text)` or `.comboList`.
    var acceptsMaxLength: Bool {
        switch type {
        case .basic(.text), .comboList: return true
        default: return false
        }
    }

    /// Clamps `text` to `maxLength`, counting `Character`s (grapheme clusters) so an emoji or a
    /// combining-mark sequence counts as one unit, not its underlying UTF-16 width. A `nil`
    /// bound is a pass-through.
    func clamped(_ text: String) -> String {
        guard let maxLength else { return text }
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength))
    }
}
