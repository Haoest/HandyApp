import Foundation

/// A physical asset owned by the user (e.g. "My House", "2022 Toyota Camry").
final class Asset: Identifiable, Equatable {
    let id: UUID
    var name: String

    /// The category this asset was created from.
    var category: AssetCategory

    /// Properties copied from the category's templates at creation time.
    /// Values are filled in per-instance; definitions come from the category snapshot.
    var baseProperties: [AssetProperty]

    /// Per-instance properties defined by the user specifically for this asset.
    var customProperties: [AssetProperty]

    /// The asset that directly contains this one (e.g. a House contains a Refrigerator).
    weak var parent: Asset?

    /// Direct children of this asset. Mutated exclusively through AssetStore hierarchy methods.
    private(set) var children: [Asset] = []

    init(
        id: UUID = UUID(),
        name: String,
        category: AssetCategory,
        baseProperties: [AssetProperty] = [],
        customProperties: [AssetProperty] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.baseProperties = baseProperties
        self.customProperties = customProperties
    }

    // MARK: - Property value convenience

    /// Returns the stored value for a given definition id, checking base then custom properties.
    func value(for definitionID: UUID) -> StoredValue? {
        if let bp = baseProperties.first(where: { $0.definition.id == definitionID }) { return bp.value }
        return customProperties.first(where: { $0.definition.id == definitionID })?.value
    }

    /// Returns the custom AssetProperty for a given definition id, if it exists.
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
