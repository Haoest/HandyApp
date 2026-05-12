import XCTest
@testable import HandyApp3

final class AssetTests: XCTestCase {

    private func makeCategory(name: String = "Test") -> AssetCategory {
        AssetCategory(name: name)
    }

    private func makeAsset(name: String = "Asset", baseProperties: [AssetProperty] = [], customProperties: [AssetProperty] = []) -> Asset {
        Asset(name: name, category: makeCategory(), baseProperties: baseProperties, customProperties: customProperties)
    }

    // value(for:) searches base properties before custom properties.
    func testValueLookupPrefersBaseOverCustom() {
        let baseDef = PropertyDefinition(name: "Color", type: .basic(.text))
        let customDef = PropertyDefinition(name: "Notes", type: .basic(.text))
        let baseProperty = AssetProperty(definition: baseDef, value: .text("Red"))
        let customProperty = AssetProperty(definition: customDef, value: .text("Custom note"))

        let asset = makeAsset(baseProperties: [baseProperty], customProperties: [customProperty])

        XCTAssertEqual(asset.value(for: baseDef.id), .text("Red"))
        XCTAssertEqual(asset.value(for: customDef.id), .text("Custom note"))
        XCTAssertNil(asset.value(for: UUID()))
    }

    // ancestors returns the chain from root down to (but not including) self.
    func testAncestorsOrdersFromRootToParent() {
        let grandparent = makeAsset(name: "Grandparent")
        let parent = makeAsset(name: "Parent")
        let child = makeAsset(name: "Child")

        grandparent._addChild(parent)
        parent._addChild(child)

        XCTAssertEqual(child.ancestors.map(\.name), ["Grandparent", "Parent"])
        XCTAssertTrue(grandparent.ancestors.isEmpty)
    }

    // descendants returns all nodes in the subtree (breadth-first, excluding self).
    func testDescendantsIncludesAllSubtreeNodes() {
        let root = makeAsset(name: "Root")
        let childA = makeAsset(name: "A")
        let childB = makeAsset(name: "B")
        let grandchild = makeAsset(name: "C")

        root._addChild(childA)
        root._addChild(childB)
        childA._addChild(grandchild)

        let names = root.descendants.map(\.name)
        XCTAssertEqual(names, ["A", "B", "C"])
    }
}
