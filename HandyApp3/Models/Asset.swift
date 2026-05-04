//
//  Asset.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

/// A physical asset owned by the user (e.g. "My House", "2022 Toyota Camry").
final class Asset: Identifiable, Equatable {
    let id: UUID
    var name: String
    var category: AssetCategory
    /// Values recorded against this asset, one entry per PropertyDefinition (sparse — not all definitions
    /// need a corresponding value).
    var propertyValues: [PropertyValue]

    /// The asset that directly contains this one (e.g. a House contains a Refrigerator).
    /// Weak to avoid a retain cycle with children.
    weak var parent: Asset?

    /// Direct children of this asset (e.g. a Refrigerator's Water Filter).
    /// Mutated exclusively through `AssetStore` hierarchy methods.
    private(set) var children: [Asset] = []

    init(
        id: UUID = UUID(),
        name: String,
        category: AssetCategory,
        propertyValues: [PropertyValue] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.propertyValues = propertyValues
    }

    // MARK: - Property value convenience

    /// Returns the stored value for a given definition id, if one exists.
    func value(for definitionID: UUID) -> PropertyValue? {
        propertyValues.first { $0.definitionID == definitionID }
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
