import XCTest
@testable import HandyApp3

final class TypeNodeTests: XCTestCase {

    // MARK: - Construction & defaults

    func testDefaultInitializerValues() {
        let node = TypeNode(name: "Appliance")
        XCTAssertEqual(node.name, "Appliance")
        XCTAssertNil(node.parent)
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertTrue(node.localFields.isEmpty)
        XCTAssertFalse(node.isAbstract)
        XCTAssertTrue(node.isUserExtensible)
        XCTAssertTrue(node.isRoot)
    }

    // MARK: - allFields: pure-append inheritance

    func testAllFieldsRootIsJustLocalFields() {
        let make = PropertyDefinition(name: "Make", type: .basic(.text))
        let appliance = TypeNode(name: "Appliance", localFields: [make])
        XCTAssertEqual(appliance.allFields.map(\.name), ["Make"])
    }

    func testAllFieldsConcatenatesParentBeforeChild() {
        let make = PropertyDefinition(name: "Make", type: .basic(.text))
        let price = PropertyDefinition(name: "Price", type: .basic(.currency))
        let powerSource = PropertyDefinition(name: "PowerSource", type: .basic(.text))

        let appliance = TypeNode(name: "Appliance", localFields: [make, price])
        let range = TypeNode(name: "Range", localFields: [powerSource])
        appliance._addChild(range)

        XCTAssertEqual(range.allFields.map(\.name), ["Make", "Price", "PowerSource"])
    }

    func testAllFieldsWalksMultipleLevels() {
        let a = PropertyDefinition(name: "A", type: .basic(.text))
        let b = PropertyDefinition(name: "B", type: .basic(.text))
        let c = PropertyDefinition(name: "C", type: .basic(.text))

        let grandparent = TypeNode(name: "G", localFields: [a])
        let parent      = TypeNode(name: "P", localFields: [b])
        let child       = TypeNode(name: "C", localFields: [c])
        grandparent._addChild(parent)
        parent._addChild(child)

        XCTAssertEqual(child.allFields.map(\.name), ["A", "B", "C"])
    }

    func testAllFieldsEmptyWhenNoFieldsAnywhere() {
        let parent = TypeNode(name: "P")
        let child = TypeNode(name: "C")
        parent._addChild(child)
        XCTAssertTrue(child.allFields.isEmpty)
    }

    func testSiblingFieldsDoNotLeakIntoEachOther() {
        let make    = PropertyDefinition(name: "Make",    type: .basic(.text))
        let powerSrc = PropertyDefinition(name: "PowerSource", type: .basic(.text))

        let appliance = TypeNode(name: "Appliance", localFields: [make])
        let range = TypeNode(name: "Range",        localFields: [powerSrc])
        let fridge = TypeNode(name: "Refrigerator", localFields: [])
        appliance._addChild(range)
        appliance._addChild(fridge)

        XCTAssertEqual(range.allFields.map(\.name),  ["Make", "PowerSource"])
        XCTAssertEqual(fridge.allFields.map(\.name), ["Make"])
    }

    // MARK: - Hierarchy traversal

    func testIsRoot() {
        let parent = TypeNode(name: "P")
        let child = TypeNode(name: "C")
        parent._addChild(child)
        XCTAssertTrue(parent.isRoot)
        XCTAssertFalse(child.isRoot)
    }

    func testAncestorsRootDownExcludingSelf() {
        let g = TypeNode(name: "G")
        let p = TypeNode(name: "P")
        let c = TypeNode(name: "C")
        g._addChild(p)
        p._addChild(c)
        XCTAssertEqual(c.ancestors.map(\.name), ["G", "P"])
        XCTAssertTrue(g.ancestors.isEmpty)
    }

    func testDescendantsBreadthFirstExcludingSelf() {
        let root = TypeNode(name: "Root")
        let a = TypeNode(name: "A")
        let b = TypeNode(name: "B")
        let a1 = TypeNode(name: "A1")
        let a2 = TypeNode(name: "A2")
        root._addChild(a)
        root._addChild(b)
        a._addChild(a1)
        a._addChild(a2)

        XCTAssertEqual(root.descendants.map(\.name), ["A", "B", "A1", "A2"])
    }

    // MARK: - Internal child management

    func testAddChildSetsParentAndAppendsToChildren() {
        let parent = TypeNode(name: "P")
        let child = TypeNode(name: "C")
        parent._addChild(child)
        XCTAssertEqual(child.parent, parent)
        XCTAssertEqual(parent.children, [child])
    }

    func testAddChildIsIdempotentByID() {
        let parent = TypeNode(name: "P")
        let child = TypeNode(name: "C")
        parent._addChild(child)
        parent._addChild(child)
        XCTAssertEqual(parent.children.count, 1)
    }

    func testRemoveChildClearsParent() {
        let parent = TypeNode(name: "P")
        let child = TypeNode(name: "C")
        parent._addChild(child)
        parent._removeChild(child)
        XCTAssertNil(child.parent)
        XCTAssertTrue(parent.children.isEmpty)
    }

    // MARK: - Equality

    func testEqualityByID() {
        let id = UUID()
        let a = TypeNode(id: id, name: "X")
        let b = TypeNode(id: id, name: "Y")  // different name, same id
        let c = TypeNode(name: "X")           // same name, different id
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
