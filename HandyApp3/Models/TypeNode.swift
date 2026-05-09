import Foundation

/// A node in the metadata type tree. Represents a kind of object an Asset can be
/// (e.g. "Appliance", "Range", "Automobile"). Nodes form an IS-A hierarchy:
/// `Range` is-a `Appliance`, so a Range inherits Appliance's `localFields`.
///
/// Inheritance is pure-append: a child can only add fields, never override or
/// suppress an ancestor's. `allFields` returns ancestors' fields (root-down)
/// followed by this node's `localFields`.
final class TypeNode: Identifiable, Equatable {
    let id: UUID
    var name: String

    /// The IS-A parent. `nil` for root nodes (top-level kinds).
    /// Weak to avoid a retain cycle with children.
    weak var parent: TypeNode?

    /// Direct subtypes. Mutated exclusively through `AssetStore` hierarchy methods.
    private(set) var children: [TypeNode] = []

    /// Fields declared directly on this node. Does not include inherited fields.
    var localFields: [PropertyDefinition]

    /// When `true`, an Asset cannot be created with this node as its `type`;
    /// only descendants can be instantiated. Useful for grouping nodes like
    /// "Appliance" that have no meaningful instances of their own.
    var isAbstract: Bool

    /// When `false`, users cannot add, edit, or remove entries in `localFields`.
    let isUserExtensible: Bool

    init(
        id: UUID = UUID(),
        name: String,
        localFields: [PropertyDefinition] = [],
        isAbstract: Bool = false,
        isUserExtensible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.localFields = localFields
        self.isAbstract = isAbstract
        self.isUserExtensible = isUserExtensible
    }

    // MARK: - Field resolution

    /// Inherited + local fields, in root-down order. Pure append — no overrides.
    var allFields: [PropertyDefinition] {
        (parent?.allFields ?? []) + localFields
    }

    // MARK: - Hierarchy traversal

    /// Ordered chain from the root ancestor down to (but not including) this node.
    var ancestors: [TypeNode] {
        var chain: [TypeNode] = []
        var cursor = parent
        while let p = cursor {
            chain.insert(p, at: 0)
            cursor = p.parent
        }
        return chain
    }

    /// All nodes in the subtree rooted at this node (breadth-first, excluding self).
    var descendants: [TypeNode] {
        var result: [TypeNode] = []
        var queue = children
        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)
            queue.append(contentsOf: node.children)
        }
        return result
    }

    /// `true` when this node has no parent.
    var isRoot: Bool { parent == nil }

    // MARK: - Internal child management (called only by AssetStore)

    func _addChild(_ child: TypeNode) {
        guard !children.contains(where: { $0.id == child.id }) else { return }
        children.append(child)
        child.parent = self
    }

    func _removeChild(_ child: TypeNode) {
        children.removeAll { $0.id == child.id }
        child.parent = nil
    }

    static func == (lhs: TypeNode, rhs: TypeNode) -> Bool {
        lhs.id == rhs.id
    }
}
