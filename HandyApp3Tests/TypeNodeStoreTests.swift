import XCTest
@testable import HandyApp3

/// Tests for the TypeNode-based AssetStore APIs added in Phase 2 of the
/// AssetCategory → TypeNode migration. The legacy category-based APIs are
/// covered in HandyApp3Tests.swift and continue to work in parallel.
final class TypeNodeStoreTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - createTypeNode

    func testCreateRootTypeNode() throws {
        let node = try store.createTypeNode(name: "Appliance", isAbstract: true)
        XCTAssertTrue(node.isRoot)
        XCTAssertTrue(node.isAbstract)
        XCTAssertEqual(store.allTypeNodes.count, 1)
        XCTAssertEqual(store.typeRoots.map(\.name), ["Appliance"])
    }

    func testCreateChildTypeNodeAttachesToParent() throws {
        let appliance = try store.createTypeNode(name: "Appliance", isAbstract: true)
        let powerSource = PropertyDefinition(name: "PowerSource", type: .basic(.text))
        let range = try store.createTypeNode(
            name: "Range",
            parentID: appliance.id,
            localFields: [powerSource]
        )
        XCTAssertEqual(range.parent, appliance)
        XCTAssertEqual(appliance.children, [range])
        XCTAssertEqual(range.allFields.map(\.name), ["PowerSource"])
        XCTAssertEqual(store.typeRoots.map(\.name), ["Appliance"])
    }

    func testCreateTypeNodeUnknownParentThrows() {
        XCTAssertThrowsError(try store.createTypeNode(name: "Range", parentID: UUID())) { error in
            if case AssetStoreError.typeNodeNotFound = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    // MARK: - createAsset(typeID:)

    func testCreateAssetFromTypeNode() throws {
        let appliance = try store.createTypeNode(
            name: "Appliance",
            localFields: [PropertyDefinition(name: "Make", type: .basic(.text))]
        )
        let asset = try store.createAsset(name: "My Fridge", typeID: appliance.id)
        XCTAssertEqual(asset.type, appliance)
        XCTAssertNil(asset.category)
        XCTAssertEqual(store.allAssets.count, 1)
    }

    func testCreateAssetUnknownTypeThrows() {
        XCTAssertThrowsError(try store.createAsset(name: "X", typeID: UUID())) { error in
            if case AssetStoreError.typeNodeNotFound = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testCreateAssetAbstractTypeThrows() throws {
        let appliance = try store.createTypeNode(name: "Appliance", isAbstract: true)
        XCTAssertThrowsError(try store.createAsset(name: "X", typeID: appliance.id)) { error in
            if case AssetStoreError.typeIsAbstract = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    // MARK: - PropertyValue resolution against TypeNode schema

    func testSetPropertyValueResolvesAgainstInheritedField() throws {
        // Field declared on parent must be settable on a child-type asset.
        let make = PropertyDefinition(name: "Make", type: .basic(.text))
        let appliance = try store.createTypeNode(name: "Appliance", localFields: [make], isAbstract: true)
        let range = try store.createTypeNode(name: "Range", parentID: appliance.id)
        let asset = try store.createAsset(name: "GE Range", typeID: range.id)

        try store.setPropertyValue(.text("GE"), forDefinitionID: make.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: make.id)?.value, .text("GE"))
    }

    func testSetPropertyValueResolvesAgainstLocalField() throws {
        let appliance = try store.createTypeNode(name: "Appliance", isAbstract: true)
        let powerSource = PropertyDefinition(name: "PowerSource", type: .basic(.text))
        let range = try store.createTypeNode(name: "Range", parentID: appliance.id, localFields: [powerSource])
        let asset = try store.createAsset(name: "GE Range", typeID: range.id)

        try store.setPropertyValue(.text("gas"), forDefinitionID: powerSource.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: powerSource.id)?.value, .text("gas"))
    }

    func testSetPropertyValueUnknownDefinitionThrows() throws {
        let range = try store.createTypeNode(name: "Range")
        let asset = try store.createAsset(name: "GE Range", typeID: range.id)
        XCTAssertThrowsError(
            try store.setPropertyValue(.text("x"), forDefinitionID: UUID(), onAssetID: asset.id)
        ) { error in
            if case AssetStoreError.definitionNotFound = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    // MARK: - schemaPropertyDefinitions

    func testSchemaPropertyDefinitionsForCategoryAsset() throws {
        let cat = store.createCategory(name: "House")
        try store.addPropertyDefinition(
            PropertyDefinition(name: "Roof Age", type: .basic(.number)),
            toCategoryID: cat.id
        )
        let asset = try store.createAsset(name: "My House", categoryID: cat.id)
        XCTAssertEqual(asset.schemaPropertyDefinitions.map(\.name), ["Roof Age"])
    }

    func testSchemaPropertyDefinitionsForTypeAsset() throws {
        let make = PropertyDefinition(name: "Make", type: .basic(.text))
        let powerSource = PropertyDefinition(name: "PowerSource", type: .basic(.text))
        let appliance = try store.createTypeNode(name: "Appliance", localFields: [make], isAbstract: true)
        let range = try store.createTypeNode(name: "Range", parentID: appliance.id, localFields: [powerSource])
        let asset = try store.createAsset(name: "GE Range", typeID: range.id)
        XCTAssertEqual(asset.schemaPropertyDefinitions.map(\.name), ["Make", "PowerSource"])
    }
}
