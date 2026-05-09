import Foundation

/// A physical asset owned by the user (e.g. "My House", "2022 Toyota Camry").
///
/// During the AssetCategory → TypeNode migration an Asset may be created via either
/// `category` (legacy path) or `type` (new path). Exactly one is expected to be set.
/// Phase 4 removes `category` and makes `type` non-optional.
final class Asset: Identifiable, Equatable {
    let id: UUID
    var name: String
    var category: AssetCategory?
    var type: TypeNode?
    /// Values recorded against this asset, one entry per PropertyDefinition (sparse — not all definitions
    /// need a corresponding value).
    var propertyValues: [PropertyValue]

    /// The asset that directly contains this one (e.g. a House contains a Refrigerator).
    /// Weak to avoid a retain cycle with children.
    weak var parent: Asset?

    /// Direct children of this asset (e.g. a Refrigerator's Water Filter).
    /// Mutated exclusively through `AssetStore` hierarchy methods.
    private(set) var children: [Asset] = []

    /// Per-instance properties defined by the user specifically for this asset.
    /// Each entry carries its own schema (PropertyDefinition) and optional value.
    var customProperties: [AssetProperty] = []

    init(
        id: UUID = UUID(),
        name: String,
        category: AssetCategory? = nil,
        type: TypeNode? = nil,
        propertyValues: [PropertyValue] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.type = type
        self.propertyValues = propertyValues
    }

    /// Schema-level property definitions visible on this asset, sourced from whichever of
    /// `category` or `type` is set. Custom (per-instance) properties are NOT included here.
    var schemaPropertyDefinitions: [PropertyDefinition] {
        if let category { return category.propertyDefinitions }
        if let type { return type.allFields }
        return []
    }

    // MARK: - Property value convenience

    /// Returns the stored value for a given definition id.
    /// Searches category-level propertyValues first, then customProperties.
    func value(for definitionID: UUID) -> PropertyValue? {
        if let pv = propertyValues.first(where: { $0.definitionID == definitionID }) { return pv }
        return customProperties.first(where: { $0.definition.id == definitionID })?.value
    }

    /// Returns the AssetProperty for a given definition id, if it exists in customProperties.
    func customProperty(for definitionID: UUID) -> AssetProperty? {
        customProperties.first { $0.definition.id == definitionID }
    }

    // MARK: - Hierarchy traversal

    /// Ordered chain from the root ancestor down to (but not including) this asset.
    var ancestors: [Asset] {
        var chain: [Asset] = []
        var cursor = parent
        while let p = cursor {
            chain.insert(p, at: 0)
            cursor = p.parent
        }
        return chain
    }

    /// All assets in the subtree rooted at this asset (breadth-first, excluding self).
    var descendants: [Asset] {
        var result: [Asset] = []
        var queue = children
        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)
            queue.append(contentsOf: node.children)
        }
        return result
    }

    /// `true` when this asset has no parent.
    var isRoot: Bool { parent == nil }

    // MARK: - Internal child management (called only by AssetStore)

    func _addChild(_ child: Asset) {
        guard !children.contains(where: { $0.id == child.id }) else { return }
        children.append(child)
        child.parent = self
    }

    func _removeChild(_ child: Asset) {
        children.removeAll { $0.id == child.id }
        child.parent = nil
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }
}
