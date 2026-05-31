import Foundation
import Observation

/// A physical asset owned by the user (e.g. "My House", "2022 Toyota Camry").
@Observable
final class Asset: Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdDate: Date
    var modifiedDate: Date

    /// The category this asset was created from.
    var category: AssetCategory

    /// Properties copied from the category's templates at creation time.
    /// Values are filled in per-instance; definitions come from the category snapshot.
    var baseProperties: [AssetProperty]

    /// Per-instance properties defined by the user specifically for this asset.
    var customProperties: [AssetProperty]

    /// ID of the asset that directly contains this one. Nil means top-level.
    var parentID: UUID?

    /// Resolved in-memory reference to the parent. Set by AssetStore hierarchy methods.
    weak var parent: Asset?

    /// Direct children of this asset. Mutated exclusively through AssetStore hierarchy methods.
    private(set) var children: [Asset] = []

    init(
        id: UUID = UUID(),
        name: String,
        category: AssetCategory,
        baseProperties: [AssetProperty] = [],
        customProperties: [AssetProperty] = [],
        parentID: UUID? = nil,
        createdDate: Date = Date(),
        modifiedDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.baseProperties = baseProperties
        self.customProperties = customProperties
        self.parentID = parentID
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
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

    // MARK: - Custom property management

    @discardableResult
    func addProperty(_ definition: PropertyDefinition, value: StoredValue? = nil) -> AssetProperty {
        let prop = AssetProperty(definition: definition, value: value)
        customProperties.append(prop)
        return prop
    }

    func removeProperty(id: UUID) {
        customProperties.removeAll { $0.id == id }
    }

    /// Changing `type` clears the stored value to avoid type mismatch.
    /// Pass `value: .some(nil)` to explicitly clear the stored value; omit to leave it unchanged.
    func updateProperty(id: UUID, name: String? = nil, type: PropertyType? = nil, isRequired: Bool? = nil, value: StoredValue?? = .none) {
        guard let prop = customProperties.first(where: { $0.id == id }) else { return }
        if let name { prop.definition.name = name }
        if let isRequired { prop.definition.isRequired = isRequired }
        if let type { prop.definition.type = type; prop.value = nil }
        if let value { prop.value = value }
    }

    // MARK: - Internal child management (called only by AssetStore)

    func _addChild(_ child: Asset) {
        guard !children.contains(where: { $0.id == child.id }) else { return }
        children.append(child)
        child.parent = self
        child.parentID = self.id
    }

    func _removeChild(_ child: Asset) {
        children.removeAll { $0.id == child.id }
        child.parent = nil
        child.parentID = nil
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }
}
