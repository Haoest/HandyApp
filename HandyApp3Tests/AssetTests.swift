import XCTest
@testable import HandyApp3

final class AssetTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

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

    func testAutomobileAssetWithCustomPropertyAndRandomizedValues() throws {
        store.seedBuiltInCategories()

        let category = try XCTUnwrap(store.allCategories.first { $0.name == SystemCategory.automobile.rawValue })
        let asset = try store.createAsset(name: "My Car", categoryID: category.id)

        // Randomize template property values
        var expectedValues: [String: StoredValue] = [:]
        for prop in asset.baseProperties {
            let value: StoredValue
            switch prop.definition.type {
            case .basic(.text):   value = .text(UUID().uuidString)
            case .basic(.number): value = .number(Double.random(in: 1900...2100))
            default: continue
            }
            try store.setPropertyValue(value, forDefinitionID: prop.definition.id, onAssetID: asset.id)
            expectedValues[prop.definition.name] = value
        }

        // Add custom "Purchase Price" property
        let priceDef = PropertyDefinition(name: "Purchase Price", type: .basic(.currency))
        let priceValue: StoredValue = .currency(10000)
        try store.addCustomProperty(definition: priceDef, value: priceValue, toAssetID: asset.id)
        expectedValues["Purchase Price"] = priceValue

        // Verify all template properties are present with correct values
        let templateNames = Set(category.propertyTemplates.map { $0.definition.name })
        XCTAssertTrue(templateNames.isSubset(of: Set(asset.baseProperties.map { $0.definition.name })))
        for prop in asset.baseProperties {
            XCTAssertEqual(prop.value, expectedValues[prop.definition.name], "Value mismatch for '\(prop.definition.name)'")
        }

        // Verify custom property is present with correct value
        let customProp = try XCTUnwrap(asset.customProperties.first { $0.definition.name == "Purchase Price" })
        XCTAssertEqual(customProp.definition.type, .basic(.currency))
        XCTAssertEqual(customProp.value, priceValue)
    }

    func testResidentialHousingAssetMatchesTemplate() throws {
        store.seedBuiltInCategories()

        let categoryName = SystemCategory.residentialHousing.rawValue
        let category = try XCTUnwrap(store.allCategories.first { $0.name == categoryName })
        let asset = try store.createAsset(name: "My House", categoryID: category.id)

        let templateNames = Set(category.propertyTemplates.map { $0.definition.name })
        let assetPropertyNames = Set(asset.baseProperties.map { $0.definition.name })
        XCTAssertEqual(assetPropertyNames, templateNames)

        let templateTypes = Dictionary(uniqueKeysWithValues: category.propertyTemplates.map { ($0.definition.name, $0.definition.type) })
        for prop in asset.baseProperties {
            XCTAssertEqual(prop.definition.type, templateTypes[prop.definition.name], "Type mismatch for '\(prop.definition.name)'")
        }

        XCTAssertTrue(asset.baseProperties.allSatisfy { $0.value == nil })
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
